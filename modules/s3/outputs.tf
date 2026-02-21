output "queue_url"  { value = aws_sqs_queue.tasks.id }
output "queue_arn"  { value = aws_sqs_queue.tasks.arn }
output "queue_name" { value = aws_sqs_queue.tasks.name }
output "dlq_url"    { value = aws_sqs_queue.dlq.id }
output "dlq_arn"    { value = aws_sqs_queue.dlq.arn }
