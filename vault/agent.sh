#!/bin/sh

DIR_PATH="/vault/config"
if [ ! -d "DIR_PATH" ]; then
  # If it doesn't exist, create the directory
  mkdir -p "$DIR_PATH"
  echo "Directory created: $DIR_PATH"
fi

export ROLE_ID_PKI="$DIR_PATH/role_id_pki"
if [ -f ROLE_ID_PKI ]; then
    rm -f "$ROLE_ID_PKI"
fi
touch "$ROLE_ID_PKI"

export SECRET_ID_PKI="$DIR_PATH/secret_id_pki"
if [ -f SECRET_ID_PKI ]; then
    rm -f "$SECRET_ID_PKI"
fi
touch "$SECRET_ID_PKI"

export TOKEN_PKI="$DIR_PATH/token_pki"
if [ -f TOKEN_PKI ]; then
    rm -f "$TOKEN_PKI"
fi
touch "$TOKEN_PKI"

vault policy fmt pki_int.hcl
vault policy write agent-policy-pki pki_int.hcl

vault auth enable approle
vault write auth/approle/role/agent-role-pki \
    token_ttl=10m \
    token_num_uses=10 \
    secret_id_ttl=10m \
    secret_id_num_uses=10 \
    policies="agent-policy-pki"

echo -e "\n# ----------  Get Vault Agent Role ID   ----------- #"
export AGENT_ROLE_ID=$(vault read -format=json auth/approle/role/agent-role-pki/role-id | jq -r .data.role_id)
echo "$AGENT_ROLE_ID" | tee $ROLE_ID_PKI

echo -e "\n# ----------  Get Vault Agent Secret ID   ----------- #"
export AGENT_SECRET_ID=$(vault write -force -format=json auth/approle/role/agent-role-pki/secret-id | jq -r .data.secret_id)
echo "$AGENT_SECRET_ID" | tee $SECRET_ID_PKI

vault write auth/approle/login  role_id="${AGENT_ROLE_ID}"  secret_id="${AGENT_SECRET_ID}"

export VAULT_TOKEN="root"
export VAULT_TOKEN=$(vault write -format=json auth/approle/login  role_id="${AGENT_ROLE_ID}"  secret_id="${AGENT_SECRET_ID}" | jq -r '.auth.client_token')
vault token lookup

export CRT_FILE_PATH="${DIR_PATH}${VAULT_SUB_DOMAIN}.crt"
export KEY_FILE_PATH="${DIR_PATH}${VAULT_SUB_DOMAIN}.key"

vault agent -config=pki-agent-config.hcl
vault agent -log-level debug -config=pki-agent-config.hcl
