# ─────────────────────────────────────────────────────────────────────────────
# MODULE: rds
# Provisions: RDS PostgreSQL primary + one read replica + subnet group
# Multi-AZ intentionally disabled (cost decision — see architecture doc)
# ─────────────────────────────────────────────────────────────────────────────

# ── DB Subnet Group ───────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.name_prefix}-db-subnet-group" }
}

# ── DB Parameter Group ────────────────────────────────────────────────────────
resource "aws_db_parameter_group" "main" {
  name   = "${var.name_prefix}-pg15-params"
  family = "postgres15"

  # Enable logical replication (required for some analytics tools)
  parameter {
    name  = "rds.logical_replication"
    value = "1"
    apply_method = "pending-reboot"
  }

  # Tune for write-heavy workloads
  parameter {
    name  = "work_mem"
    value = "16384" # 16MB per sort/hash operation
  }

  tags = { Name = "${var.name_prefix}-pg15-params" }
}

# ── Primary RDS Instance ──────────────────────────────────────────────────────
resource "aws_db_instance" "primary" {
  identifier        = "${var.name_prefix}-postgres-primary"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true # Encryption at rest

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  parameter_group_name   = aws_db_parameter_group.main.name

  # Backups — 7 day retention, automated
  backup_retention_period = 7
  backup_window           = "02:00-03:00" # UTC — low traffic window
  maintenance_window      = "sun:04:00-sun:05:00"

  # Multi-AZ disabled (cost decision — see architecture doc §10)
  # Enable when enterprise SLAs require < 1 min RTO
  multi_az = false

  # Prevent accidental deletion in production
  deletion_protection = false # Set true in production
  skip_final_snapshot = true  # Set false in production

  # Performance Insights for query-level diagnostics
  performance_insights_enabled = true

  tags = { Name = "${var.name_prefix}-postgres-primary", Role = "primary" }
}

# ── Read Replica ──────────────────────────────────────────────────────────────
# Routes analytics and read-heavy queries away from the primary
resource "aws_db_instance" "replica" {
  identifier          = "${var.name_prefix}-postgres-replica"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.instance_class
  storage_encrypted   = true

  vpc_security_group_ids = [var.rds_sg_id]

  # Replicas do not need their own backup config
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled = true

  tags = { Name = "${var.name_prefix}-postgres-replica", Role = "read-replica" }
}
