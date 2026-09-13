# AWS FinOps Agent with MCP

Agent conversationnel qui répond en langage naturel à des questions sur les coûts et l'utilisation de sa propre infrastructure AWS, exposé comme serveur MCP et hébergé sur Amazon Bedrock AgentCore.

## Fonctionnalités

- « Combien m'ont coûté mes instances GPU les 7 derniers jours ? » (AWS Cost Explorer)
- « Quelles instances tournent avec un GPU sous-utilisé ? » (CloudWatch)
- « Quel est mon coût par million de tokens servis ? »

## Architecture

- **Hébergement** : Amazon Bedrock AgentCore (Runtime + Gateway)
- **Données** : AWS Cost Explorer API et CloudWatch, via un rôle IAM strictement en lecture seule
- **Déploiement** : Terraform (`00-IAM.tf`, `01-BEDROCK.tf`, `02-MCP.tf`)
- **Protocole** : les outils sont exposés comme un serveur MCP plutôt qu'un schéma d'outils propriétaire Bedrock

```mermaid
flowchart TD
    subgraph Client["Client de démo"]
        CLI["Claude Code CLI"]
        Chat["claude.ai (connecteur MCP distant)"]
    end

    subgraph AgentCore["Amazon Bedrock AgentCore"]
        GW["Gateway (MCP target, spec 2026-07-28)"]
        RT["Runtime (boucle agent, MCP à état)"]
    end

    subgraph MCPServer["Serveur MCP (02-MCP.tf)"]
        T1["cost_by_service_period"]
        T2["active_gpu_instances"]
        T3["gpu_utilization_rate"]
    end

    subgraph AWSData["Données AWS (rôle IAM lecture seule, 00-IAM.tf)"]
        CE["Cost Explorer API"]
        CW["CloudWatch"]
    end

    CLI --> GW
    Chat --> GW
    GW --> RT
    RT --> T1
    RT --> T2
    RT --> T3
    T1 --> CE
    T2 --> CW
    T3 --> CW
```

## Sécurité

- **Frontière internet / AWS** : seul le Gateway MCP est exposé publiquement, en HTTPS/TLS 1.2+ avec authentification requise ; le Runtime, le serveur MCP et les appels aux API AWS restent internes au compte (pas de sortie internet depuis Cost Explorer / CloudWatch)
- **Chiffrement** : TLS en transit sur tous les flux (client → Gateway, appels API AWS), chiffrement au repos natif sur Cost Explorer et CloudWatch
- **Moindre privilège** : rôle IAM dédié, lecture seule (`ce:Get*`, `cloudwatch:Get*`/`List*`), aucune permission d'écriture — défini dans `00-IAM.tf`

```mermaid
flowchart TD
    subgraph Internet["Internet (non maîtrisé)"]
        CLI["Claude Code CLI"]
        Chat["claude.ai"]
    end

    subgraph AWSAccount["Compte AWS — VPC privé"]
        GW["Gateway MCP<br/>TLS 1.2+, authentification requise"]
        RT["Runtime<br/>boucle agent, MCP à état"]

        subgraph MCPServer["Serveur MCP (02-MCP.tf)"]
            T1["cost_by_service_period"]
            T2["active_gpu_instances"]
            T3["gpu_utilization_rate"]
        end

        Role["Rôle IAM lecture seule (00-IAM.tf)<br/>deny write, scope ce:Get*, cloudwatch:Get*/List*"]

        subgraph APIsAWS["APIs AWS internes — pas de sortie Internet"]
            CE["Cost Explorer API<br/>chiffré au repos + TLS en transit"]
            CW["CloudWatch<br/>chiffré au repos + TLS en transit"]
        end
    end

    CLI -->|HTTPS, TLS 1.2+| GW
    Chat -->|HTTPS, TLS 1.2+| GW
    GW --> RT
    RT --> T1
    RT --> T2
    RT --> T3
    T1 -.->|assume role| Role
    T2 -.->|assume role| Role
    T3 -.->|assume role| Role
    Role --> CE
    Role --> CW
```

## Démo

*(captures d'écran / asciinema à ajouter — démo via Claude Code CLI et/ou un connecteur MCP distant sur claude.ai)*

## Contexte du projet

Scope, décisions et critère d'arrêt : voir [finops-mcp-agent.md](finops-mcp-agent.md).
