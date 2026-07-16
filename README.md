# terraform-multi-env-demo

用 Terraform 管理的 AWS EKS 多环境（dev / prod）基础设施项目。目录分离方案，两个环境各自拥有独立的 VPC、EKS 集群、Remote State，互不干扰。dev 环境验证基础设施骨架能否跑通，prod 环境在此基础上补齐生产级流量入口能力。

## 目录结构

```
terraform-multi-env-demo/
├── .github/workflows/
│   ├── dev-terraform.yml       # 仅 environments/dev/** 变更触发
│   └── prod-terraform.yml      # 仅 environments/prod/** 变更触发
├── environments/
│   ├── dev/
│   │   ├── main.tf              # provider 配置、调用 modules/vpc
│   │   ├── eks.tf               # EKS 集群、IAM Role、Access Entry
│   │   ├── node.tf              # Node Group + Node IAM Role
│   │   ├── helm.tf              # kube-prometheus-stack Helm Release
│   │   ├── addon.tf             # EKS Addon(vpc-cni、coredns 等)
│   │   ├── backend.tf           # S3 remote state,dev 专属 key
│   │   └── variables.tf
│   └── prod/
│       ├── main.tf
│       ├── eks.tf
│       ├── node.tf
│       ├── helm.tf              # 监控栈 + AWS Load Balancer Controller + Ingress Nginx
│       ├── irsa.tf              # IRSA 权限体系(dev 没有)
│       ├── iam_policy.json      # AWS Load Balancer Controller 自定义权限清单
│       ├── backend.tf           # S3 remote state,prod 专属 key
│       └── variable.tf
├── modules/vpc/
│   ├── vpc.tf                   # VPC 本体
│   ├── subnet.tf                # 3 AZ × (public + private) 子网
│   ├── nat.tf                   # NAT Gateway + EIP,按 AZ 独立
│   ├── variables.tf
│   └── output.tf                # 对外暴露 subnet ids 等
├── .gitignore
└── README.md
```

Prod 相对 dev，多出 `irsa.tf` 和 `iam_policy.json` 两个文件，`helm.tf` 的内容也从单一的监控栈部署，扩展为"监控栈 + LB Controller + Ingress Nginx"三者。

## 为什么选目录分离，而不是 `terraform workspace`

两种方案都能做到 state 隔离，但目录分离额外提供了：

- **物理隔离**：dev 和 prod 是两套完全独立的目录、变量文件，误操作的可能性更低。`workspace` 是同一份代码切换 state，容易在切错 workspace 时把 dev 的操作打到 prod。
- **允许结构分叉**：dev 和 prod 允许配置结构本身不同（比如 prod 多一层 IRSA、多一套流量入口），workspace 模式下两边共用同一份 `.tf` 代码，做不到这一点。
- **代价**：`modules/vpc` 之外的部分有少量重复，但换来的是更低的误操作风险，对生产环境这笔账划算。

## 网络架构：3 可用区高可用

`modules/vpc` 按 3 个可用区（AZ）设计：

```
每个 AZ(ap-southeast-1a / 1b / 1c)各自一套：
  ├── 1 个 public 子网  →  路由表指向 IGW(全局共用 1 个，IGW 不绑定 AZ)
  ├── 1 个 private 子网 →  路由表指向本 AZ 专属的 NAT Gateway
  └── 1 个 NAT Gateway(绑定 1 个 EIP)
```

- 3 public 子网 + 3 private 子网 + 3 NAT Gateway + 3 EIP，通过 `count = 3` 和 `count.index` 生成。
- Public 路由表全局共用 1 个（IGW 没有 AZ 绑定的限制），private 路由表按 AZ 各自独立（NAT Gateway 有 AZ 绑定，必须一一对应）。
- EKS worker node 放在 private 子网，不直接暴露公网。

## Prod：生产级流量入口架构

```
公网请求
  ↓
ALB(由 AWS Load Balancer Controller 创建,不在 Terraform state 中直接管理)
  ↓
Ingress Nginx Controller(Helm 部署,Service type=LoadBalancer 触发上一步)
  ↓
Ingress 规则(域名/路径转发)
  ↓
后端 Service(ClusterIP,如 Grafana)
```

**核心设计：LB 不是被"创建"出来的，是被"申请"出来的。** Ingress Nginx 的 Service 声明（`type: LoadBalancer` + annotation）是一份申请，AWS Load Balancer Controller 持续监听这类声明，发现后代表你调用 AWS API 真正建出 ALB。这一整条链路，Terraform state 里看不到 ALB 本身——它是 K8s 运行时自动创建的资源，销毁环境前需要先 `kubectl delete` 相关 Service，再 `terraform destroy`，否则会有孤儿 AWS 资源残留。

## IRSA（IAM Roles for Service Accounts）

AWS Load Balancer Controller 需要调用 AWS API（建 ALB、改安全组），但它只是一个跑在 pod 里的第三方开源程序，默认没有任何 AWS 权限。IRSA 解决"如何让这一个 pod、且仅这一个 pod，安全获得所需 AWS 权限"的问题，对应 `irsa.tf`：

| 步骤 | 资源 | 作用 |
|---|---|---|
| 1 | `aws_iam_openid_connect_provider` | 让 AWS IAM 能识别该 EKS 集群签发的身份证明格式（OIDC） |
| 2 | `data.aws_iam_policy_document`（Trust Policy） | 精确限定"只有 `kube-system` 命名空间下、名为 `aws-load-balancer-controller` 的 Service Account"才能借用这个角色，并限定用途仅限 AWS STS（`sub` / `aud` 双重 condition） |
| 3 | `aws_iam_policy` + `aws_iam_role_policy_attachment` | 自定义权限清单（建 ALB、改安全组、查 VPC 等），来自官方 [kubernetes-sigs/aws-load-balancer-controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller) 维护的 `iam_policy.json`（存于 `environments/prod/iam_policy.json`），非 AWS 官方托管策略，需自行下载并创建 |
| 4 | `aws_iam_role` | 挂载 Trust Policy（资格）+ Permission Policy（能力），两者独立存在，分别管理 |
| 5 | `kubernetes_service_account` | 在 K8s 侧创建对应身份，通过 `eks.amazonaws.com/role-arn` annotation 与 IAM Role 关联 |

**Trust Policy 与 Permission Policy 的分工：** 前者只回答"谁能借用这个角色"（不含任何业务权限），后者只回答"借到之后能做什么"。两者独立维护，便于分别调整信任范围与能力范围，不互相牵连。

## Helm 部署

`helm.tf` 中两个 `helm_release`，顺序依赖不能颠倒：

1. **`aws-load-balancer-controller`** — 先部署，作为持续运行的"审批人"。通过 `serviceAccount.create=false` + `serviceAccount.name` 指定使用 IRSA 创建的 Service Account，而非让 Helm 自行新建（否则拿到的账号没有 AWS 权限）。
2. **`ingress-nginx`**（`depends_on` 上一个）— Ingress Nginx Controller 本身，其 Service 配置 `type: LoadBalancer`，即触发上一步 Controller 去创建 ALB。

dev 环境的 `helm.tf` 只部署 `kube-prometheus-stack`（Prometheus + Grafana），没有流量入口相关内容。

## State 隔离

两个环境共用同一个 S3 bucket（`elden-state-bucket`），靠不同的 key 隔离：

| 环境 | Backend Key |
|---|---|
| dev  | `environments/dev/terraform.tfstate` |
| prod | `environments/prod/terraform.tfstate` |

Locking 使用 Terraform 1.10+ 的 `use_lockfile = true` 机制，未使用已弃用的 DynamoDB 锁表方案。

## CI/CD

`.github/workflows/` 下 dev 与 prod 各自独立一份 workflow，与"目录分离而非 workspace"的隔离原则保持一致：

```
.github/workflows/
├── dev-terraform.yml    # 仅 environments/dev/** 变更触发
└── prod-terraform.yml   # 仅 environments/prod/** 变更触发
```

- 触发条件：push / pull_request 到 `main`，通过 `paths` 过滤器限定只响应对应环境目录的变更，避免两份 workflow 互相触发。
- 每个 workflow 通过 `defaults.run.working-directory` 指定进入对应环境目录执行 `terraform init/plan`。
- `terraform apply` 未接入自动触发，通过 GitHub Environments 设置人工审批网关。
- AWS 凭证、敏感变量通过 GitHub Secrets 注入，不写入代码。

## 环境变量与密钥管理

- 敏感值一律通过 `terraform.tfvars` 提供，该文件已在 `.gitignore` 中排除，不提交到仓库。
- `iam_policy.json` 是公开的第三方权限清单，不含敏感信息，正常提交到仓库（这是让代码可复现所必需的文件，不属于需要排除的类别）。
- Helm values 中的密码通过变量引用，不写死明文。
- CI 环境中通过 GitHub Secrets 注入凭证，同样不落地到代码。

## 使用方式

```bash
# 以 dev 为例
cd environments/dev
terraform init      # 读取 backend.tf，连接到 dev 专属的 S3 state key
terraform plan
terraform apply

# prod 同理，但目录不同，state 完全独立
cd environments/prod
terraform init
terraform plan       # 建议先只跑 plan，确认无误再决定是否 apply
```

## 技术栈

- Terraform 1.15.6 / hashicorp/aws provider v6.53.0
- AWS EKS（ap-southeast-1）、VPC、NAT Gateway、ALB、S3（remote state）
- Helm（kube-prometheus-stack 监控栈 + AWS Load Balancer Controller + Ingress Nginx）
- GitHub Actions（CI，dev/prod 独立 workflow）
