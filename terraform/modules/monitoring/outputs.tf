output "notification_channel" {
  description = "通知先（メール）のチャンネル"
  value       = google_monitoring_notification_channel.email.name
}
