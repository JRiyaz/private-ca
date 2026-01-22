FROM hashicorp/vault:1.18.1

RUN apk --no-cache add jq openssl

WORKDIR /vault

ENV VAULT_ADDR=http://127.0.0.1:8200
ENV VAULT_TOKEN=root
ENV VAULT_NAMESPACE=''

COPY vault-dev-server.hcl commands.sh pki_int.hcl new_cert.sh app-crt.ctmpl app-key.ctmpl pki-agent-config.hcl agent.sh cert_with_ca.sh .env ./

# Fix Windows CRLF line endings and make scripts executable
RUN sed -i 's/\r$//' *.sh && chmod +x *.sh

#ENTRYPOINT ["vault", "server", "-config=/vault/vault.json"]
ENTRYPOINT ["vault", "server"]

# Pass development mode and root token as environment variables for runtime
#CMD ["-dev", "-dev-root-token-id=root"]
CMD ["-dev", "-dev-root-token-id=root", "-dev-listen-address=0.0.0.0:8200", "-config=/vault/vault-dev-server.hcl"]
