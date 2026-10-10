output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "instance_profile" {
  value = aws_iam_instance_profile.node.name
}
