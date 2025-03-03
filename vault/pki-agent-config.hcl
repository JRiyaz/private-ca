pid_file = "./pidfile"

vault {
  address = "http://127.0.0.1:8200"
  retry {
    num_retries = 1
  }
}

auto_auth {
  method {
    type      = "approle"
    config = {
      role_id_file_path = "/vault/config/role_id_pki"
      secret_id_file_path = "/vault/config/secret_id_pki"
      remove_secret_id_file_after_reading = false
    }
  }
  sink {
    type = "file"
    config = {
      path = "/vault/config/token_pki"
    }
  }
}

listener "tcp" {
  address = "127.0.0.1:8100"
  tls_disable = true
}

template {
  source      = "./app-crt.ctmpl"
  destination = "/vault/certs/localhost.com/localhost.crt"
}

template {
  source      = "./app-key.ctmpl"
  destination = "/vault/certs/localhost.com/localhost.key"
}
