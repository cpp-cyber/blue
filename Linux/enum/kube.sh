# I refuse to manually write these out

# Get all mostly relevant secrets
kubectl get secrets -o json -A | jq '.items[] | del(.data.release, .data."tls.crt", .data."tls.key", .data."ca.crt", .data."kubeconfig") | {name: .metadata.name, data} | select(.data != {})'

# Get all privileged pods 
kubectl get pods -o json -A | jq '.items[] | { podname: .metadata.name, namespace: .metadata.namespace, securitycontext: .spec.containers[].securityContext } '| jq -s '.' | jq ' .[] | select( .securitycontext != null ) | select( .securitycontext.privileged == true )' | jq -s '.' | jq ' group_by( .namespace )[] | { ( .[0].namespace ): [ .[] | { podname: .podname, security: .securitycontext } ] }'

# All exposed nodeports
kubectl get service -A -o json | jq '.items[] | { name: .metadata.name, namespace: .metadata.namespace, ports: .spec.ports } | select( .ports[].nodePort != null ) '

# List ingresses
kubectl get ingress -A -o json | jq '.items[] | { spec: .spec } | .[].rules '

# List funny envvars
kubectl get pod -A -o json | jq '.items[] | { namespace: .metadata.namespace, name: .metadata.name, envvar: .spec.containers[].env } | select(.envvar != null) | select( any( .envvar[]; .name | test("(?i)(ADMIN|PASSWORD|USER)" ) ) )'
