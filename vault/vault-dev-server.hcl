ui                    = true

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/localhost.com/vault.localhost.crt"
  tls_key_file  = "/vault/certs/localhost.com/vault.localhost.key"
}
