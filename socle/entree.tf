# Adresses IP publiques fixes du point d'entrée des applications, une par zone de disponibilité.
# Elles restent dans le socle pour survivre à la destruction du cluster : le nom DuckDNS pointe toujours vers elles.
# Le nom DuckDNS pointe vers celle de la zone a ; le NLB répartit ensuite entre les zones.
resource "aws_eip" "entree" {
  for_each = toset(["a", "b", "c"])
  domain   = "vpc"
  tags     = { Name = "gitops-dev-entree-${each.key}" }
}

output "entree_ip"             { value = aws_eip.entree["a"].public_ip }
output "entree_allocation_ids" { value = join(",", [for z in ["a", "b", "c"] : aws_eip.entree[z].allocation_id]) }
