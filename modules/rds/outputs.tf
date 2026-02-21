output "db_endpoint" {
  value     = aws_db_instance.primary.endpoint
  sensitive = true
}

output "replica_endpoint" {
  value     = aws_db_instance.replica.endpoint
  sensitive = true
}

output "db_identifier" {
  value = aws_db_instance.primary.identifier
}
