output "zone_id" {
  description = "The zone ID"
  value       = aws_route53_zone.staging.zone_id
  # value       = module.route53-hostedzone.zone_id
}

output "name_servers" {
  description = "The hosted zone name servers"
  value       = aws_route53_zone.staging.name_servers
  # value       = module.route53-hostedzone.name_servers
}

output "domain_name" {
  value = local.domain_name
}
