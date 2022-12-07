#!/usr/bin/env bash
set +x

# WARNING: this script is used by the GitHub Actions automation and isn't necessarily designed to be consumed directly.

# set defaults that can be overridden
INSPECTION_TAG=${INSPECTION_TAG:-master}
BUNDLE_TAG=${BUNDLE_TAG:-nightly-head}
SGO_BUNDLE_RESULT_DIR=${SGO_BUNDLE_RESULT_DIR:-${GITHUB_WORKSPACE}/sgo-bundle}
STO_BUNDLE_RESULT_DIR=${STO_BUNDLE_RESULT_DIR:-${GITHUB_WORKSPACE}/sto-bundle}
SGO_BUNDLE_IMAGE_PATH=quay.io/infrawatch-operators/smart-gateway-operator-bundle
STO_BUNDLE_IMAGE_PATH=quay.io/infrawatch-operators/service-telemetry-operator-bundle
INDEX_IMAGE_PATH=quay.io/infrawatch-operators/infrawatch-catalog
INDEX_IMAGE_TAG=${INDEX_IMAGE_TAG:-nightly}

echo "SGO result dir: ${SGO_BUNDLE_RESULT_DIR}"
echo "STO result dir: ${STO_BUNDLE_RESULT_DIR}"

# login to quay.io registry so we can push bundles to infrawatch-operators organization
echo "${QUAY_INFRAWATCH_OPERATORS_PASSWORD}" | docker login -u="${QUAY_INFRAWATCH_OPERATORS_USERNAME}" --password-stdin quay.io || exit

# Smart Gateway Operator bundle creation

# -- Get hashes for images so they can be replaced in the bundle manifest for relatedImages
echo "-- Get Smart Gateway Operator image hash"
SG_OPERATOR_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/smart-gateway-operator:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)

echo "-- Get sg-core image hash"
SG_CORE_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/sg-core:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)

echo "-- Get sg-bridge image hash"
SG_BRIDGE_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/sg-bridge:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)

echo "-- Create Smart Gateway Operator bundle"
pushd "${GITHUB_WORKSPACE}/smart-gateway-operator/" || exit
mkdir "${SGO_BUNDLE_RESULT_DIR}"
WORKING_DIR=${SGO_BUNDLE_RESULT_DIR} ./build/generate_bundle.sh
popd || exit

echo "-- Replace tag with hash for image paths in Smart Gateway Operator"
sed -i "s#quay.io/infrawatch/smart-gateway-operator:${INSPECTION_TAG}#quay.io/infrawatch/smart-gateway-operator@${SG_OPERATOR_IMAGE_HASH}#g" "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"
sed -i "s#quay.io/infrawatch/sg-core:${INSPECTION_TAG}#quay.io/infrawatch/sg-core@${SG_CORE_IMAGE_HASH}#g" "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"
sed -i "s#quay.io/infrawatch/sg-bridge:${INSPECTION_TAG}#quay.io/infrawatch/sg-bridge@${SG_BRIDGE_IMAGE_HASH}#g" "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"

# Service Telemetry Operator bundle creation

# -- Get hashes for images so they can be replaced in the bundle manifest for relatedImages
echo "-- Get Service Telemetry Operator image hash"
ST_OPERATOR_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/service-telemetry-operator:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)
echo "## Service telemetry operator image hash: ${ST_OPERATOR_IMAGE_HASH}"

echo "-- Get Prometheus Webhook SNMP image hash"
PROMETHEUS_WEBHOOK_SNMP_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/prometheus-webhook-snmp:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)
echo "## Prometheus webhook SNMP image hash: ${PROMETHEUS_WEBHOOK_SNMP_IMAGE_HASH}"

echo "-- Create Service Telemetry Operator bundle"
pushd "${GITHUB_WORKSPACE}/service-telemetry-operator/" || exit
mkdir "${STO_BUNDLE_RESULT_DIR}"
WORKING_DIR=${STO_BUNDLE_RESULT_DIR} ./build/generate_bundle.sh
popd || exit

echo "-- Replace tag with hash for image paths for Service Telemetry Operator"
sed -i "s#quay.io/infrawatch/service-telemetry-operator:${INSPECTION_TAG}#quay.io/infrawatch/service-telemetry-operator@${ST_OPERATOR_IMAGE_HASH}#g" "${STO_BUNDLE_RESULT_DIR}/manifests/service-telemetry-operator.clusterserviceversion.yaml"
sed -i "s#quay.io/infrawatch/prometheus-webhook-snmp:${INSPECTION_TAG}#quay.io/infrawatch/prometheus-webhook-snmp@${PROMETHEUS_WEBHOOK_SNMP_IMAGE_HASH}#g" "${STO_BUNDLE_RESULT_DIR}/manifests/service-telemetry-operator.clusterserviceversion.yaml"

# -- Validate, build, and push bundles
echo "-- Validate bundles"
for bundle in ${SGO_BUNDLE_RESULT_DIR} ${STO_BUNDLE_RESULT_DIR}
do
    operator-sdk bundle validate "${bundle}"
done

echo "-- Build and push Smart Gateway Operator bundle image"
pushd "${SGO_BUNDLE_RESULT_DIR}" || exit
docker build --tag "${SGO_BUNDLE_IMAGE_PATH}:${BUNDLE_TAG}" --file Dockerfile .
SGO_BUNDLE_IMAGE_HASH=$(docker push "${SGO_BUNDLE_IMAGE_PATH}:${BUNDLE_TAG}" | sed -n -e 's/^.*\(sha256:.*\)\(size.*\)$/\1/p' | tr -d '[:space:]')
popd || exit


echo "-- Build and push Service Telemetry Operator bundle image"
pushd "${STO_BUNDLE_RESULT_DIR}" || exit
docker build --tag "${STO_BUNDLE_IMAGE_PATH}:${BUNDLE_TAG}" --file Dockerfile .
STO_BUNDLE_IMAGE_HASH=$(docker push "${STO_BUNDLE_IMAGE_PATH}:${BUNDLE_TAG}" | sed -n -e 's/^.*\(sha256:.*\)\(size.*\)$/\1/p' | tr -d '[:space:]')
popd || exit

echo "-- Build and push index image"
opm index add --build-tool docker --bundles "${SGO_BUNDLE_IMAGE_PATH}@${SGO_BUNDLE_IMAGE_HASH},${STO_BUNDLE_IMAGE_PATH}@${STO_BUNDLE_IMAGE_HASH}" --from-index "${INDEX_IMAGE_PATH}:${INDEX_IMAGE_TAG}" --tag "${INDEX_IMAGE_PATH}:${INDEX_IMAGE_TAG}" || exit
docker push "${INDEX_IMAGE_PATH}:${INDEX_IMAGE_TAG}" || exit
