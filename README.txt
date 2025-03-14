### Using Cert-Manager with HashiCorp Vault
    # https://genekuo.medium.com/using-hashicorp-vault-as-certificate-manager-on-a-kubernetes-cluster-155604d39a60

### CERT MANAGER (https://cert-manager.io/docs/installation/helm/)
1. Add Cert Manager repo
    helm repo add jetstack https://charts.jetstack.io --force-update

2. Install Cert Manager
    helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --version v1.17.1 --set crds.enabled=true

### HashiCorp Vault (https://developer.hashicorp.com/vault/docs/platform/k8s/helm)
1. Links
    https://developer.hashicorp.com/vault/tutorials/archive/kubernetes-cert-manager

2. Add Vault repo
    helm repo add hashicorp https://helm.releases.hashicorp.com

3. Search available Vault versions
    helm search repo hashicorp/vault -l

4. Install Vault
    1. helm install vault hashicorp/vault --version 0.29.1 --create-namespace --namespace vault
    2. helm install vault hashicorp/vault --set "injector.enabled=false" --version 0.29.1 --create-namespace --namespace vault

5. Edit Vault service and change the type from ClusterIP to NodePort
    kubectl edit service/vault -n vault

6. Exec inside the pod to unseal
    kubectl exec -it vault-0 -n vault -- sh

7. Generate initial keys
    1. kubectl exec vault-0 -n vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json > init-keys.json
    2. vault operator init -key-shares=1 -key-threshold=1 -format=json > init-keys.json
vault write pki/config/urls issuing_certificates="http://localhost:8200/v1/pki/ca" crl_distribution_points="http://localhost:8200/v1/pki/crl"
8. Unseal vault
    1. Install jq (choco install jq)
    2. cat init-keys.json | jq -r ".unseal_keys_b64[]"

    export VAULT_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")

    1. kubectl exec vault-0 -n vault -- vault operator unseal $VAULT_UNSEAL_KEY
    2. vault operator unseal $VAULT_UNSEAL_KEY

9. Login to Vault
    cat init-keys.json | jq -r ".root_token"

    export VAULT_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")

    1. kubectl exec vault-0 -n vault -- vault login $VAULT_ROOT_TOKEN
    2. vault login $VAULT_ROOT_TOKEN

### Configure Vault with existing CA
1. Links
    1. Import CA certificates and keys (https://developer.hashicorp.com/vault/api-docs/secret/pki#import-ca-certificates-and-keys)
    2. https://discuss.hashicorp.com/t/not-able-to-import-certificate-bundle/52721
    3. https://groups.google.com/g/vault-tool/c/y4IcgiLBG4c

2. Enable PKI engine
    vault secrets enable pki

3. convert private key from pkcs8 format to pkcs1 format
    # https://groups.google.com/g/vault-tool/c/y4IcgiLBG4c/m/2MUcsNrNDAAJ

    openssl rsa -in ./certs/localhost.com/ca_root-private_key.key -out root-pkcs1.key -outform pem

4. Bundle ca-root.pem and root-pkcs1.key
    cat ./certs/localhost.com/ca-root.pem root-pkcs1.key > ca-root-bundle.pem

5. Feed ca-bundle
    # IGNORE: below setup if 3rd and 4th setups are done.
    # Copy ca-root.pem and ca_root-private_key.key into ca-bundle.pem and feed it to below command

    vault write pki/config/ca pem_bundle=@ca-root-bundle.pem

6. Check the issuers list
    vault list pki/issuers

7. Check the keys list
    vault list pki/keys

8. Configure the urls for root CA
    vault write pki/config/urls issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"

### Configure Vault with existing Intermediate CA
1. Enable pki_int engine
    vault secrets enable -path=pki_int pki

2. convert private key from pkcs8 format to pkcs1 format
    # https://groups.google.com/g/vault-tool/c/y4IcgiLBG4c/m/2MUcsNrNDAAJ

    openssl rsa -in ./certs/localhost.com/ca_inter-private_key.key -out inter-pkcs1.key -outform pem

3. Bundle ca-inter.pem and inter-pkcs1.key
    cat ./certs/localhost.com/ca-inter.pem inter-pkcs1.key > ca-inter-bundle.pem

2. Feed ca-inter-bundle.pem to below command
    vault write pki_int/config/ca pem_bundle=@ca-inter-bundle.pem

3. **** (Optional) ****, not sure if this setup is required or not
    vault write pki_int/intermediate/set-signed certificate=@ca-inter.pem

4. Configure URL for intermediate CA
    vault write pki_int/config/urls issuing_certificates="http://127.0.0.1:8200/v1/pki_int/ca" crl_distribution_points="http://127.0.0.1:8200/v1/pki_int/crl"

### Start Nginx
docker run --rm -v E:/k8/private-ca/vault/certs:/etc/nginx/certs -v E:/k8/private-ca/web-server:/etc/nginx/conf.d --name nginx -p 80:80 -p 443:443 nginx

### Ingress setup
    1. Links:
        https://medium.com/@dikkumburage/how-to-install-nginx-ingress-controller-93a375e8edde

    2. helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

    2. helm install ingress-nginx ingress-nginx/ingress-nginx -f ingress.yaml

        Example:
            An example Ingress that makes use of the controller:
            apiVersion: networking.k8s.io/v1
            kind: Ingress
            metadata:
                name: example
                namespace: foo
            spec:
                ingressClassName: nginx
                rules:
                - host: www.example.com
                    http:
                    paths:
                        - pathType: Prefix
                        backend:
                            service:
                            name: exampleService
                            port:
                                number: 80
                        path: /
                # This section is only required if TLS is to be enabled for the Ingress
                tls:
                - hosts:
                    - www.example.com
                    secretName: example-tls

            If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

            apiVersion: v1
            kind: Secret
            metadata:
                name: example-tls
                namespace: foo
            data:
                tls.crt: <base64 encoded cert>
                tls.key: <base64 encoded key>
            type: kubernetes.io/tls
    