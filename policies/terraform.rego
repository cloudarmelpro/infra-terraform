package main

import rego.v1

# 1. Aucun accès SSH ouvert à tout Internet
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_vpc_security_group_ingress_rule"
	rc.change.after.cidr_ipv4 == "0.0.0.0/0"
	rc.change.after.from_port <= 22
	rc.change.after.to_port >= 22
	msg := sprintf("%s : SSH ouvert sur Internet", [rc.address])
}

deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_security_group_rule"
	rc.change.after.type == "ingress"
	"0.0.0.0/0" in rc.change.after.cidr_blocks
	rc.change.after.from_port <= 22
	rc.change.after.to_port >= 22
	msg := sprintf("%s : SSH ouvert sur Internet", [rc.address])
}

# 2. Étiquettes d'images immuables dans ECR
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_ecr_repository"
	rc.change.after.image_tag_mutability != "IMMUTABLE"
	msg := sprintf("%s : les étiquettes d'images doivent être immuables", [rc.address])
}

# 3. Chaque compartiment S3 a une configuration de chiffrement explicite
deny contains msg if {
	nb_buckets := count([rc | some rc in input.resource_changes; rc.type == "aws_s3_bucket"])
	nb_chiffrement := count([rc | some rc in input.resource_changes; rc.type == "aws_s3_bucket_server_side_encryption_configuration"])
	nb_buckets > nb_chiffrement
	msg := sprintf("%d compartiment(s) S3 sans chiffrement explicite", [nb_buckets - nb_chiffrement])
}

# 4. L'API EKS n'est pas ouverte à tout Internet
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "aws_eks_cluster"
	some vc in rc.change.after.vpc_config
	vc.endpoint_public_access == true
	"0.0.0.0/0" in vc.public_access_cidrs
	msg := sprintf("%s : l'API EKS est ouverte à tout Internet", [rc.address])
}
