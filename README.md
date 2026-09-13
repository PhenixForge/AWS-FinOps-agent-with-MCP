# AWS FinOps Agent with MCP

[![Terraform](https://img.shields.io/badge/Terraform-v1.6%2B-7B42BC?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS_Provider-v6.0%2B-FF9900?logo=amazonaws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![Python](https://img.shields.io/badge/Python-3.13-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![MCP](https://img.shields.io/badge/MCP-Model_Context_Protocol-000000.svg)](https://modelcontextprotocol.io/)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Julien-blue?logo=linkedin)](https://www.linkedin.com/in/julien-p-68834731/?locale=fr)

Agent conversationnel qui répond en langage naturel à des questions sur les coûts et l'utilisation de sa propre infrastructure AWS, exposé comme serveur MCP et hébergé sur Amazon Bedrock AgentCore.

## Fonctionnalités

- « Combien m'ont coûté mes instances GPU les 7 derniers jours ? » (AWS Cost Explorer)
- « Quelles instances tournent avec un GPU sous-utilisé ? » (CloudWatch)
- « Quel est mon coût par million de tokens servis ? »

## Pourquoi c'est agentique, et pourquoi MCP

Ce n'est pas un LLM qui répond depuis ses connaissances générales sur AWS — c'est un système où l'agent décide lui-même quels outils appeler, dans quel ordre et avec quels paramètres, pour répondre à une question qu'il n'a jamais vue formulée exactement comme ça. Le split entre outils (3 fonctions étroites et déterministes : coût, instances GPU, utilisation) et agent (la boucle qui orchestre) est le cœur de la démarche : pas un pipeline figé, un plan généré à la volée.

L'exemple qui me plaît le plus pour illustrer ça :

> « Quelles instances tournent avec un GPU sous-utilisé ? » n'existe comme fonction nulle part dans `handler.py`. L'agent doit décomposer tout seul : lister les instances GPU actives, interroger le taux d'utilisation de chacune, corréler les deux résultats, et appliquer un seuil pour juger "sous-utilisé". Personne n'a écrit cette logique de composition — elle émerge du raisonnement de l'agent sur les 3 outils disponibles.

Ça infuse aussi l'architecture : le rôle IAM lecture seule, l'authz sur le Gateway, tout ça existe parce qu'on donne un accès réel — bien que restreint — à de l'infra de prod à un système autonome, pas à un chatbot qui répondrait depuis un dashboard pré-calculé.

Côté protocole, j'ai délibérément choisi MCP plutôt que le schéma d'action groups propriétaire de Bedrock, alors que ce dernier aurait été tout aussi capable techniquement. La raison est stratégique plus que technique : MCP découple les outils du client qui les consomme. Les mêmes 3 tools servent à Claude Code CLI et à claude.ai sans écrire deux intégrations différentes — avec un schéma Bedrock, ce choix n'existerait pas, ce serait Bedrock ou rien. Et si demain le modèle change, un `aws_bedrockagentcore_gateway_target` en MCP reste utilisable, alors qu'un schéma d'action group est jetable dès qu'on change d'écosystème agent. C'est le pari de la commoditisation évoqué dans [finops-mcp-agent.md](finops-mcp-agent.md) : si n'importe quel modèle sait de mieux en mieux faire du tool-use, la valeur se déplace du modèle vers la couche d'intégration — et c'est cette couche-là que ce projet met en avant.

## Architecture

- **Hébergement** : Amazon Bedrock AgentCore Gateway (MCP), authentification OAuth via Cognito (`CUSTOM_JWT`)
- **Outils** : une Lambda (`finops-tools`) implémente les 3 outils, enregistrée sur le Gateway comme cible MCP
- **Données** : AWS Cost Explorer API, EC2 et CloudWatch, via un rôle IAM strictement en lecture seule
- **Déploiement** : Terraform (`00-IAM.tf`, `03-BEDROCK-gateway.tf`, `04-MCP.tf` — `01-ECR.tf`/`02-BEDROCK-runtime.tf` sont un chantier annexe optionnel, voir plus bas)
- **Protocole** : les outils sont exposés comme un serveur MCP plutôt qu'un schéma d'outils propriétaire Bedrock

```mermaid
flowchart TD
    subgraph Client["Client de démo"]
        CLI["Claude Code CLI"]
        Chat["claude.ai (connecteur MCP distant)"]
    end

    subgraph AgentCore["Amazon Bedrock AgentCore Gateway"]
        GW["Gateway (MCP, auth Cognito/CUSTOM_JWT)"]
    end

    subgraph MCPServer["Lambda finops-tools (04-MCP.tf)"]
        T1["cost_by_service_period"]
        T2["active_gpu_instances"]
        T3["gpu_utilization_rate"]
    end

    subgraph AWSData["Données AWS (rôle IAM lecture seule)"]
        CE["Cost Explorer API"]
        EC2["EC2 (describe)"]
        CW["CloudWatch"]
    end

    CLI --> GW
    Chat --> GW
    GW --> T1
    GW --> T2
    GW --> T3
    T1 --> CE
    T2 --> EC2
    T3 --> CW
```

Un Runtime AgentCore conteneurisé (`01-ECR.tf`, `02-BEDROCK-runtime.tf`) existe aussi dans le repo mais n'est **pas nécessaire à cette démo** : Claude Code CLI et claude.ai fournissent déjà leur propre boucle agent et parlent directement au Gateway ci-dessus. Il est gardé de côté comme chantier exploratoire pour tester, séparément, un agent autonome invocable en dehors de tout client MCP (nécessite encore un Dockerfile + du code, non écrit).

## Sécurité

- **Réseau** : pas de VPC privé — choix délibéré, pas un oubli : AWS Cost Explorer n'a pas de support VPC PrivateLink, donc même en subnet privé il aurait fallu un NAT Gateway (~35$/mois) pour l'atteindre, sans gain de sécurité réel puisque le trafic reste public dans les deux cas. Détail complet dans [finops-mcp-agent.md](finops-mcp-agent.md#retour-dexpérience--réseau-public-vs-vpc-privé-13-septembre-2026).
- **Chiffrement** : TLS en transit sur tous les flux (client → Gateway MCP, Lambda → API AWS), chiffrement au repos natif sur Cost Explorer et CloudWatch
- **Authentification** : le Gateway MCP exige un token OAuth (Cognito, `CUSTOM_JWT`) pour tout appel entrant
- **Moindre privilège** : la Lambda `finops-tools` a son propre rôle IAM dédié, lecture seule (`ce:Get*`, `cloudwatch:Get*`/`List*`, `ec2:Describe*`), aucune permission d'écriture — le rôle du Gateway, séparé, ne peut qu'invoquer cette Lambda

```mermaid
flowchart TD
    subgraph Internet["Internet"]
        CLI["Claude Code CLI"]
        Chat["claude.ai"]
    end

    subgraph AWSAccount["Compte AWS"]
        GW["Gateway MCP<br/>OAuth (Cognito, CUSTOM_JWT)"]

        subgraph MCPServer["Lambda finops-tools (04-MCP.tf)"]
            T1["cost_by_service_period"]
            T2["active_gpu_instances"]
            T3["gpu_utilization_rate"]
        end

        Role["Rôle IAM lecture seule de la Lambda<br/>deny write, scope ce:Get*, cloudwatch:Get*/List*, ec2:Describe*"]
    end

    subgraph APIsAWS["APIs AWS publiques — pas de PrivateLink sur Cost Explorer"]
        CE["Cost Explorer API<br/>chiffré au repos + TLS en transit"]
        EC2["EC2 describe<br/>TLS en transit"]
        CW["CloudWatch<br/>chiffré au repos + TLS en transit"]
    end

    CLI -->|HTTPS, OAuth token| GW
    Chat -->|HTTPS, OAuth token| GW
    GW --> T1
    GW --> T2
    GW --> T3
    T1 -.->|assume role| Role
    T2 -.->|assume role| Role
    T3 -.->|assume role| Role
    Role -->|HTTPS, TLS 1.2+| CE
    Role -->|HTTPS, TLS 1.2+| EC2
    Role -->|HTTPS, TLS 1.2+| CW
```

## Démo

*(captures d'écran / asciinema à ajouter — démo via Claude Code CLI et/ou un connecteur MCP distant sur claude.ai)*

## Contexte du projet

Scope, décisions et critère d'arrêt : voir [finops-mcp-agent.md](finops-mcp-agent.md).
