# Login and sanity check
export VAULT_ADDR=http://localhost:8200
vault login root
vault status

# Enable root pki and set max ttl
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

# Create root CA
vault write -format=json pki/root/generate/internal \
  common_name="LocalHost Certificate Authority" \
  issuer_name="LocalHost-Inc" \
  ttl=87600h > pki-root.json

# Extract root certs
jq -r '.data.certificate' pki-root.json > ca-root.pem

# Configure root CA URLs
vault write pki/config/urls \
  issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
  crl_distribution_points="$VAULT_ADDR/v1/pki/crl"

# Enable intermediate pki and set max ttl
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=87600h pki_int

# Create intermediate CA
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="LocalHost Intermediate Authority" \
  issuer_name="LocalHost-Intermediate-Inc" > pki-int.csr.json

# Extract CSR
jq -r '.data.csr' pki-int.csr.json > pki-int.csr

# Sign intermediate CA with root CA
vault write -format=json pki/root/sign-intermediate \
  csr=@pki-int.csr \
  format=pem_bundle \
  ttl=87600h \
  issuer_ref="LocalHost-Inc" > pki-int-signed.json

# Extract signed intermediate certs
jq -r '.data.certificate' pki-int-signed.json > ca-inter.pem

# Activate signed intermediate CA
vault write pki_int/intermediate/set-signed \
  certificate=@ca-inter.pem

# Configure intermediate CA URLs
vault write pki_int/config/urls \
  issuing_certificates="$VAULT_ADDR/v1/pki_int/ca" \
  crl_distribution_points="$VAULT_ADDR/v1/pki_int/crl"

# Create role for issuing leaf certificates
vault write pki_int/roles/server-role \
  allowed_domains="localhost.com,www.localhost.com" \
  allow_bare_domains=true \
  allow_subdomains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  server_flag=true \
  client_flag=false \
  key_type="rsa" \
  key_bits=2048 \
  max_ttl=87000h

# Issue a leaf certificate
vault write -format=json pki_int/issue/server-role \
  common_name="localhost.com" \
  alt_names="localhost,www.localhost.com" \
  ip_sans="127.0.0.1" > localhost.json

# Generate CA and intermediate CA crt files
openssl x509 \
  -in ca-root.pem \
  -outform der \
  -out ca-root.crt

openssl x509 \
  -in ca-inter.pem \
  -outform der \
  -out ca-inter.crt

# Extract issued certificate and key
jq -r '.data.certificate' localhost.json > localhost.crt
jq -r '.data.issuing_ca' localhost.json >> localhost.crt
jq -r '.data.private_key' localhost.json > localhost.key

# Trust the root CA in the local system (example for Linux)
# sudo security add-trusted-cert \
#   -d -r trustRoot \
#   -k /Library/Keychains/System.keychain \
#   ca-root.pem

# Kill safari browser
# killall Safari

# Cert installation verfication
# openssl x509 -in localhost.crt -text -noout

# The above command must show below result
# X509v3 Subject Alternative Name:
#   DNS:localhost.com
#   DNS:localhost
#   IP Address:127.0.0.1

# X509v3 Extended Key Usage:
#   TLS Web Server Authentication
