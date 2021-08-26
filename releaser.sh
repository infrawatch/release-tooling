#!/usr/bin/env bash
set +x

# WARNING: this script is used by the automation and isn't necessary designed to be consumed directly.

# set defaults that can be overridden
INSPECTION_TAG=${INSPECTION_TAG:-latest}
BUNDLE_TAG=${BUNDLE_TAG:-nightly-head}
SGO_BUNDLE_RESULT_DIR=${SGO_BUNDLE_RESULT_DIR:-${GITHUB_WORKSPACE}/sgo-bundle}
STO_BUNDLE_RESULT_DIR=${STO_BUNDLE_RESULT_DIR:-${GITHUB_WORKSPACE}/sto-bundle}

# login to quay.io registry so we can push bundles to infrawatch-operators organization
echo "${QUAY_INFRAWATCH_OPERATORS_PASSWORD}" | docker login -u="${QUAY_INFRAWATCH_OPERATORS_USERNAME}" --password-stdin quay.io || exit

# Smart Gateway Operator bundle creation
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

echo "-- Replace tag with hash for image paths"
sed -i "s#quay.io/infrawatch/smart-gateway-operator:${INSPECTION_TAG}#quay.io/infrawatch/smart-gateway-operator@${SG_OPERATOR_IMAGE_HASH}#g" "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"
sed -i "s#quay.io/infrawatch/sg-core:${INSPECTION_TAG}#quay.io/infrawatch/sg-core@${SG_CORE_IMAGE_HASH}#g" "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"
sed -i "s#quay.io/infrawatch/sg-bridge:${INSPECTION_TAG}#quay.io/infrawatch/sg-bridge@${SG_BRIDGE_IMAGE_HASH}#g" "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"
cat "${SGO_BUNDLE_RESULT_DIR}/manifests/smart-gateway-operator.clusterserviceversion.yaml"

# Service Telemetry Operator bundle creation
echo "-- Get Service Telemetry Operator image hash"
ST_OPERATOR_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/service-telemetry-operator:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)
echo "## Service telemetry operator image hash: ${ST_OPERATOR_IMAGE_HASH}"

echo "-- Get Prometheus Webhook SNMP image hash"
PROMETHEUS_WEBHOOK_SNMP_IMAGE_HASH=$(skopeo inspect docker://quay.io/infrawatch/prometheus-webhook-snmp:"${INSPECTION_TAG}" | jq -c '.Digest' | sed -e 's/^"//' -e 's/"$//' -)
echo "## Prometheus webhook SNMP image hash: ${PROMETHEUS_WEBHOOK_SNMP_IMAGE_HASH}"

echo "-- Create Service Telemetry Operator bundle"
STO_BUNDLE_RESULT_DIR=${GITHUB_WORKSPACE}/sto-bundle/
pushd "${GITHUB_WORKSPACE}/service-telemetry-operator/" || exit
mkdir "${STO_BUNDLE_RESULT_DIR}"
WORKING_DIR=${STO_BUNDLE_RESULT_DIR} ./build/generate_bundle.sh
popd || exit

echo "-- Replace tag with hash for image paths"
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
pwd ; ls -lah
docker build --tag "quay.io/infrawatch-operators/smart-gateway-operator-bundle:${BUNDLE_TAG}" --file Dockerfile .
popd || exit


echo "-- Build and push Service Telemetry Operator bundle image"
pushd "${STO_BUNDLE_RESULT_DIR}" || exit
pwd ; ls -lah
docker build --tag "quay.io/infrawatch-operators/service-telemetry-operator-bundle:${BUNDLE_TAG}" --file Dockerfile .
# docker push
popd || exit

echo "-- Build and push index image"
# opm stuff
