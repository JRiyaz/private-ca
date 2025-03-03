#!/bin/sh

VAULT_ROOT_DOMAIN="$VAULT_ROOT_DOMAIN"
VAULT_ROOT_DOMAIN_URL="$VAULT_ROOT_DOMAIN_URL"
VAULT_ALT_NAMES="$VAULT_ALT_NAMES"
VAULT_REQUIRED_DOMAIN="$VAULT_REQUIRED_DOMAIN"
VAULT_SUB_DOMAIN="$VAULT_SUB_DOMAIN"
VAULT_USER="$VAULT_USER"
VAULT_PASSWORD="$VAULT_PASSWORD"
CERT_PATH="$CERT_PATH"
LEAF_CA_TTL="$LEAF_CA_TTL"
ROLE_TTL="$ROLE_TTL"
INTER_ISSUER_NAME="$INTER_ISSUER_NAME"
ORGANIZATION_NAME="$ORGANIZATION_NAME"
ORGANIZATION_UNIT="$ORGANIZATION_UNIT"

vault login root
vault status
vault audit enable file file_path=/vault/logs/vault_audit.log
vault audit enable -path="file_raw" file  log_raw=true file_path=/vault/logs/vault_audit_raw.log

vault secrets enable pki

openssl rsa -in /vault/certs/"${CERT_PATH}"/ca_root-private_key.key -out root-pkcs1.key -outform pem

cat /vault/certs/"${CERT_PATH}"/ca-root.pem root-pkcs1.key > ca-root-bundle.pem

vault write pki/config/ca pem_bundle=@ca-root-bundle.pem

vault list pki/issuers

vault list pki/keys

vault write pki/config/urls issuing_certificates="${VAULT_ADDR}/v1/pki/ca" crl_distribution_points="${VAULT_ADDR}/v1/pki/crl"

vault secrets enable -path=pki_int pki

openssl rsa -in /vault/certs/"${CERT_PATH}"/ca_inter-private_key.key -out inter-pkcs1.key -outform pem

cat /vault/certs/"${CERT_PATH}"/ca-inter.pem inter-pkcs1.key > ca-inter-bundle.pem

vault write pki_int/config/ca pem_bundle=@ca-inter-bundle.pem

vault write pki_int/config/urls issuing_certificates="${VAULT_ADDR}/v1/pki_int/ca" crl_distribution_points="${VAULT_ADDR}/v1/pki_int/crl"


export ROLES_PATH="pki_int/roles/${VAULT_ROOT_DOMAIN_URL}"
vault write "${ROLES_PATH}" allowed_domains="${VAULT_ROOT_DOMAIN}" allow_subdomains=true issuer_ref="$(vault read -field=default pki_int/config/issuers)" country="IN" locality="Bengaluru" street_address="SouthEnd Road" organization="${ORGANIZATION_NAME}" ou="${ORGANIZATION_UNIT}" postal_code="560004" province="English, Hindi" max_ttl="${ROLE_TTL}"

#          **************** POLICY ****************
vault policy fmt pki_int.hcl
vault policy write pki_int pki_int.hcl

vault auth enable userpass
# shellcheck disable=SC2086
vault write auth/userpass/users/"${VAULT_USER}" password=${VAULT_PASSWORD} token_policies="pki_int"

# Generate certificate
# shellcheck disable=SC2086
vault login -format=json -method=userpass username=${VAULT_USER} password=${VAULT_PASSWORD} | jq -r .auth.client_token > user.token
# shellcheck disable=SC2006
export VAULT_TOKEN=`cat user.token`

### GENERATE LEAF CERTIFICATE
vault write -format=json pki_int/issue/"${VAULT_ROOT_DOMAIN_URL}" common_name="${VAULT_REQUIRED_DOMAIN}" issuer_ref="${INTER_ISSUER_NAME}" alt_names="${VAULT_ALT_NAMES}" ttl="${LEAF_CA_TTL}" > "${VAULT_SUB_DOMAIN}".json

# shellcheck disable=SC2002
cat "${VAULT_SUB_DOMAIN}".json | jq -r .data.certificate > /vault/certs/"${CERT_PATH}"/"${VAULT_SUB_DOMAIN}".crt
# shellcheck disable=SC2002
cat "${VAULT_SUB_DOMAIN}".json | jq -r .data.issuing_ca >> /vault/certs/"${CERT_PATH}"/"${VAULT_SUB_DOMAIN}".crt
# shellcheck disable=SC2002
cat "${VAULT_SUB_DOMAIN}".json | jq -r .data.private_key > /vault/certs/"${CERT_PATH}"/"${VAULT_SUB_DOMAIN}".key
