terraform {
	# Backend S3 (recommandé pour un usage partagé)
	# Décommentez ce bloc et renseignez les valeurs adaptées à votre environnement.
	# backend "s3" {
	#   bucket         = "aws-finops-terraform-state"
	#   key            = "finops/terraform.tfstate"
	#   region         = "eu-west-1"
	#   encrypt        = true
	#   dynamodb_table = "terraform-state-lock"
	# }

	# Backend local (développement local)
	# Un seul backend peut être actif à la fois.
	backend "local" {
		path = "terraform.tfstate"
	}
}
