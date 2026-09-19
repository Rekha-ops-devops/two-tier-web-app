resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "project2-rds-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags = { Name = "project2-rds-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier             = "project2-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "project2db"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az               = true
  skip_final_snapshot    = true
  publicly_accessible    = false
}