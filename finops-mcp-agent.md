# Mini-projet : agent FinOps AWS + MCP
Agent FinOps AWS en langage naturel, exposé via MCP, hébergé sur Bedrock AgentCore.

---
name: finops-mcp-agent
description: >
  Mini-projet portfolio "quick win" — agent FinOps AWS en langage naturel, exposé via MCP,
  hébergé sur Bedrock AgentCore. Décidé et cadré en septembre 2026, distinct du projet
  flagship vllm-serving-kubernetes-platform. À consulter pour tout ce qui concerne ce
  projet, son scope, ses décisions et son critère d'arrêt.
---

# Terraform setup on Fedora Gnome

Sur Fedora Gnome 44, on utilise le package manager `dnf` :

```bash
sudo dnf install -y dnf5-plugins
sudo dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install -y terraform
terraform -version
```

## Contexte et raison d'être

Expérimentation pratique sur l'agentique. Volontairement un **repo séparé** du projet flagship `vllm-serving-kubernetes-platform` (voir `vllm-serving-kub-pf.md`) — ne doit ni le retarder ni se confondre avec lui.

**Objectif** : produire, en une session de travail en copilotage avec un LLM de codage, un agent conversationnel qui répond à des questions réelles sur les coûts et l'utilisation de sa propre infrastructure AWS — pas un énième tutoriel d'agent générique.

## Scope retenu

- **Fonction** : répondre en langage naturel à des questions comme « combien m'ont coûté mes instances GPU les 7 derniers jours ? », « quelles instances tournent avec un GPU sous-utilisé ? », « quel est mon coût par million de tokens servis ? »
- **Hébergement** : Amazon Bedrock AgentCore (Runtime + Gateway) — supporte nativement MCP depuis 2026 (spec MCP 2026-07-28 côté Gateway, MCP à état côté Runtime depuis mars 2026)
- **Données** : AWS Cost Explorer API (coût par service/période) et CloudWatch (utilisation GPU des instances)
- **Déploiement** : Terraform, rôle IAM strictement en lecture seule sur facturation et métriques
- **Protocole** : les fonctions outils sont exposées comme un **serveur MCP** plutôt qu'un schéma d'outils propriétaire Bedrock — incarne la thèse de la commoditisation des appels modèles (la valeur se déplace vers la couche protocole/intégration, pas le modèle lui-même)

## Explicitement hors scope (et pourquoi)

- **GCP** : cloud-agnostique écarté — doubler les clouds double la friction d'auth/IAM que le copilotage ne compresse pas, et va à l'encontre de la consigne de ne pas investir de temps personnel sur GCP (à apprendre en heures de bureau chez Valeo uniquement)
- **RAG et évaluation** : reportés sur le projet vLLM flagship, où ils s'intègrent plus naturellement (un modèle déjà servi, une stack Prometheus déjà en place) et où le calendrier n'est pas contraint par un objectif de livraison rapide

## Découpage de la session (repères, pas un budget rigide)

1. Préparation compte : accès modèle Bedrock, activation Cost Explorer, rôle IAM lecture seule
2. Écriture des 3 fonctions outils (coût par service/période, instances GPU actives, taux d'utilisation) + boucle agent
3. Emballage en serveur MCP (léger avec copilotage — les fonctions existent déjà, il s'agit de les exposer au format MCP)
4. Déploiement Terraform sur AgentCore
5. README avec schéma d'architecture, captures d'écran, transcription réelle question/réponse
6. Post LinkedIn en anglais

## Critère d'arrêt

Si l'agent ne répond pas de bout en bout à une vraie question le premier soir : publier le repo avec ce qui fonctionne et un README honnête sur ce qui bloque, ou abandonner proprement. Pas de glissement..

## Façade de démo — tranché (12 septembre 2026)

Claude Desktop est écarté comme client de démo : la bêta Linux (juillet 2026) ne supporte officiellement que les distributions Debian/Ubuntu — Fedora et RHEL en sont explicitement exclus (confirmé sur la documentation officielle, à revérifier si Julien change de distribution). La démo passera par :

- **Claude Code CLI** en priorité — tourne nativement sur Fedora Workstation GNOME sans les contraintes de la bêta Desktop, s'intègre au workflow de copilotage déjà utilisé sur ce projet, démo terminal enregistrée (capture d'écran ou asciinema) montrant une vraie question/réponse sur la facturation AWS. Ce format terminal est aussi cohérent, voire plus crédible, pour une audience infra que pour un public grand public.
- **Un connecteur MCP distant ajouté sur claude.ai** en option complémentaire si un rendu plus conversationnel (bulle de chat plutôt que terminal) est voulu pour le post LinkedIn — accessible depuis n'importe quel navigateur, sans dépendance à Desktop.

## Budget

Quelques euros au maximum avec un modèle économique — l'agent lit des données de facturation existantes, aucun GPU nécessaire pour le projet lui-même.

## Retour d'expérience : réseau public vs VPC privé (13 septembre 2026)

Piste explorée puis abandonnée : héberger le Runtime AgentCore en mode réseau `VPC` (subnets privés + security group dédié) plutôt qu'en `PUBLIC`, pour coller au schéma sécurité du README.

Abandonnée en creusant un point non évident : **AWS Cost Explorer ne supporte pas du tout VPC PrivateLink** — son API n'est joignable que via l'endpoint public, quel que soit le mode réseau choisi. Un Runtime en subnet privé aurait donc quand même eu besoin d'une sortie internet (NAT Gateway) juste pour appeler Cost Explorer, ce qui n'apporte aucune amélioration de sécurité réelle : le trafic sort en HTTPS public dans les deux cas, seule la route change. Or un NAT Gateway coûte environ 32-35 $/mois — largement au-dessus du budget "quelques euros" du projet, pour re-router un appel qui reste public de toute façon.

**Décision** : `network_mode = "PUBLIC"` sur le Runtime. La frontière de sécurité réelle (authentification sur le Gateway MCP, rôle IAM strictement lecture seule) ne dépend pas de ce choix — elle est déjà couverte ailleurs. Ressources VPC (`main.tf`) conservées pour les autres subnet groups (DB/ElastiCache), mais le security group dédié au Runtime a été retiré, devenu inutile.

**Leçon générale** : sur AWS, certains services managés (Cost Explorer, mais d'autres existent) n'ont tout simplement pas d'équivalent PrivateLink — le "tout privé" n'est pas toujours atteignable, et vouloir l'imposer partout peut faire payer un coût réseau (NAT) sans gain de sécurité réel. À vérifier service par service avant de figer une contrainte d'architecture.

## Décision : Gateway + Lambda plutôt que Runtime pour la démo (13 septembre 2026)

En construisant `04-MCP.tf`, constat : les clients de démo prévus (Claude Code CLI, connecteur MCP claude.ai) embarquent déjà leur propre boucle agent. Le Runtime AgentCore (`02-BEDROCK-runtime.tf` + ECR), qui héberge sa propre boucle agent + appel modèle Bedrock, ne reçoit donc jamais d'appel dans ce scénario — rien ne l'invoque.

**Décision** : la démo repose uniquement sur Gateway + une Lambda (`finops-tools`) exposant les 3 outils en MCP — plus simple, gratuit/quasi-gratuit, et sans Dockerfile ni code de boucle agent à écrire. Le Runtime et l'ECR sont conservés dans le repo comme chantier exploratoire séparé, pour tester plus tard le pattern "agent conteneurisé autonome" invocable indépendamment de tout client MCP (cas d'usage : un appelant sans LLM propre, ex. un bot Slack ou un job planifié) — non nécessaire pour ce projet, gardé par intérêt technique.

## À faire / à vérifier une fois un compte AWS disponible (13 septembre 2026)

Rien de tout ça n'est bloquant pour continuer à coder, mais tout nécessite soit un vrai déploiement, soit un accès compte pour être réglé ou confirmé. Liste pour ne rien perdre :

- **Domaine Cognito manquant** (`aws_cognito_user_pool_domain`) — sans lui, l'endpoint OAuth `/oauth2/token` n'existe pas, donc le flow `client_credentials` ne peut délivrer aucun token. Pur code Terraform, pas besoin d'un compte pour l'écrire, mais impossible à tester sans déployer.
- **Aucun `output` Terraform** pour récupérer après coup l'URL du Gateway, le `client_id`/`client_secret` Cognito et le domaine — nécessaires pour configurer un vrai client MCP (Claude Code CLI, claude.ai). Idem : à écrire, mais à valider seulement après un `apply`.
- **Forme exacte de l'event Lambda envoyé par le Gateway** (target MCP `lambda`) — `handler.py` tente plusieurs formes plausibles, à confirmer/adapter après une première invocation réelle (logguer `event` tel quel).
- **Principal/`source_arn` de `aws_lambda_permission`** (`04-MCP.tf`) — supposé `bedrock-agentcore.amazonaws.com` + ARN du Gateway, non vérifié contre la doc AWS.
- **Namespace/nom de métrique CloudWatch pour le GPU** (`handler.py`, `gpu_utilization_rate`) — suppose un agent CloudWatch/NVIDIA DCGM publiant sous `CWAgent`/`nvidia_smi_utilization_gpu` ; dépend de ce qui est réellement installé sur les instances GPU, à ajuster une fois qu'elles existent.
- **Service principal AgentCore** (`00-IAM.tf`) déjà confirmé contre la doc — pas un TODO, juste listé ici pour mémoire que c'est réglé.
