# terraform-multi-env-demo

用 Terraform 管理的 AWS EKS 多环境（dev / prod）基础设施 Demo。目录分离方案，两个环境各自拥有独立的 VPC、EKS 集群、Remote State，互不干扰。

## 项目背景

单环境的 Terraform 项目（一套 state、一套变量）没法反映真实公司的运作方式——测试环境和生产环境必须物理隔离，任何一边的操作都不能影响另一边。这个项目把原本的单环境结构，改造成能同时管理 dev 和 prod 两套完全独立环境的标准结构。

## 架构

```
terraform-multi-env-demo/
├── modules/
│   └── vpc/                    # 可复用 VPC 模块，dev/prod 共用同一份代码
│       ├── vpc.tf
│       ├── subnet.tf
│       ├── variables.tf
│       └── output.tf
├── environments/
│   ├── dev/
│   │   ├── main.tf              # 调用 modules/vpc，传入 dev 专属变量
│   │   ├── eks.tf
│   │   ├── node.tf
│   │   ├── addon.tf
│   │   ├── helm.tf
│   │   ├── variables.tf
│   │   ├── terraform.tfvars     # 未提交（.gitignore），含真实敏感值
│   │   └── backend.tf           # 指向 S3 的 dev 专属 state key
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       ├── terraform.tfvars
│       └── backend.tf           # 指向 S3 的 prod 专属 state key
└── .github/workflows/
    └── terraform-plan.yml       # CI：push/PR 自动 terraform plan
```

### 为什么选目录分离，而不是 `terraform workspace`

两种方案都能做到 state 隔离，但目录分离额外提供了：

- **物理隔离**：dev 和 prod 是两套完全独立的目录、变量文件，误操作的可能性更低。`terraform workspace` 是同一份代码切换 state，容易在切错 workspace 时把 dev 的操作打到 prod。
- **可以自由 diverge**：dev 和 prod 未来允许配置结构本身不同（比如 prod 多加一层审批、多一个模块），workspace 模式下两边共用同一份 `.tf` 代码，做不到这一点。
- **代价**：`modules/vpc` 之外的部分有少量重复（每个环境各自的 `main.tf`），但换来的是更低的误操作风险，对生产环境这笔账划算。

## 网络架构：3 可用区高可用

`modules/vpc` 内部按 3 个可用区（AZ）设计，不是单 AZ：

```
每个 AZ（ap-southeast-1a / 1b / 1c）各自一套：
  ├── 1 个 public 子网  →  路由表指向 IGW（全局共用 1 个，IGW 不绑定 AZ）
  ├── 1 个 private 子网 →  路由表指向本 AZ 专属的 NAT Gateway
  └── 1 个 NAT Gateway（绑定 1 个 EIP）
```

- 3 public 子网 + 3 private 子网 + 3 NAT Gateway + 3 EIP，通过 `count = 3` 和 `count.index` 生成，避免手写 6+ 个重复 resource block。
- Public 路由表全局共用 1 个（IGW 没有 AZ 绑定的限制），private 路由表按 AZ 各自独立（NAT Gateway 有 AZ 绑定，必须一一对应，否则某个 AZ 的 NAT 故障会连带影响其他 AZ）。
- EKS worker node 只放在 private 子网，不直接暴露公网。

## State 隔离

两个环境共用同一个 S3 bucket（`elden-state-bucket`），靠不同的 **key** 隔离，不会互相覆盖：

| 环境 | Backend Key |
|---|---|
| dev  | `environments/dev/terraform.tfstate` |
| prod | `environments/prod/terraform.tfstate` |

Locking 使用 Terraform 1.10+ 的 `use_lockfile = true` 机制（原生锁文件），未使用已弃用的 DynamoDB 锁表方案。

## CI/CD

`.github/workflows/terraform-plan.yml`：

- 触发条件：push / pull_request 到 `main`
- 自动执行 `terraform init` + `terraform plan`
- `terraform apply` 未接入自动触发，通过 GitHub Environments 设置人工审批网关
- AWS 凭证、敏感变量（如 Grafana 密码）通过 GitHub Secrets 注入，不写入代码

## 环境差异

dev 和 prod 除 VPC CIDR、State Key 相互独立外，规格上刻意区分（dev 用小规格以控制练习期间的 AWS 费用）：

| | dev | prod |
|---|---|---|
| 用途 | 日常开发验证 | 生产（仅验证 `plan`，未真实 apply） |
| 规格 | 小规格 Node Group | 更大规格 / 多副本 |

## 环境变量与密钥管理

- 敏感值（密码、账号 ID）一律通过 `terraform.tfvars` 提供，该文件已在 `.gitignore` 中排除，不提交到仓库。
- Helm values 中的密码（如 `grafana.adminPassword`）通过 `var.password` 引用，不写死明文。
- CI 环境中通过 GitHub Secrets（`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`、`TF_VAR_gfpassword` 等）注入，同样不落地到代码。

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
- AWS EKS（ap-southeast-1）、VPC、NAT Gateway、S3（remote state）
- Helm（kube-prometheus-stack 监控栈）
- GitHub Actions（CI）
