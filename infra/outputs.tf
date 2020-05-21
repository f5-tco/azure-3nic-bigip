#AKS outputs
#output "client_certificate" { value = "${module.aks.client_certificate}"}
# output "kube_config" {  value = "${module.aks.kube_config}"}

#BIGIP outputs
output "vm01mgmtpip" {  value = "${module.bigip.vm01mgmtpip}"}

#Verification outputs
