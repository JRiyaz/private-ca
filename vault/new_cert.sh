#!/bin/sh

REQUIRED_DOMAIN="$REQUIRED_DOMAIN"
SUB_DOMAIN="$SUB_DOMAIN"



VAULT_ROOT_DOMAIN_URL="$VAULT_ROOT_DOMAIN_URL"
CERT_PATH="$CERT_PATH"
LEAF_CA_TTL="$LEAF_CA_TTL"
INTER_ISSUER_NAME="$INTER_ISSUER_NAME"

vault write -format=json pki_int/issue/"${VAULT_ROOT_DOMAIN_URL}" common_name="${REQUIRED_DOMAIN}" issuer_ref="${INTER_ISSUER_NAME}" alt_names="www.${REQUIRED_DOMAIN}" ttl="${LEAF_CA_TTL}" > "${SUB_DOMAIN}".json

# shellcheck disable=SC2002
cat "${SUB_DOMAIN}".json | jq -r .data.certificate > /vault/certs/"${CERT_PATH}"/"${SUB_DOMAIN}".crt
# shellcheck disable=SC2002
cat "${SUB_DOMAIN}".json | jq -r .data.issuing_ca >> /vault/certs/"${CERT_PATH}"/"${SUB_DOMAIN}".crt
# shellcheck disable=SC2002
cat "${SUB_DOMAIN}".json | jq -r .data.private_key > /vault/certs/"${CERT_PATH}"/"${SUB_DOMAIN}".key
