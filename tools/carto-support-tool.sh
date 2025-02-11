#!/bin/bash

#  CARTO 3 Self hosted dump kubernetes info
#
# Usage:
#   dump_carto_info.sh --n <namespace> --release <helm_release> --engine <engine> [--extra]
#

_bad_arguments() {
	echo "Missing or bad arguments"
	_print_help
	exit 1
}

_print_help() {
	cat <<-EOF

		usage: bash $0 [-h] --namespace NAMESPACE --release HELM_RELEASE --engine ENGINE [--gcp-project] [--extra] 

		mandatory arguments:
			--namespace NAMESPACE                                                    e.g. carto
			--release   HELM_RELEASE                                                 e.g. carto
			--engine    ENGINE                                                       specify your kubernetes cluster engine, e.g. gke, aks, eks or custom

		optional arguments:
			--extra                                                                  download all cluster info, this option need to run containers in your kubernetes cluster to obtain extra checks
			--gcp-project                                                            in case of GKE engine, specify your GCP project in which Kubernetes is deployed
			-h, --help                                                               show this help message and exit

	EOF
}

_main() {
	ARGS=("$@")
    # <!-- markdownlint-disable-next-line SC3030 -->
	for index in "${!ARGS[@]}"; do
		case "${ARGS[index]}" in
		"--namespace")
			NAMESPACE="${ARGS[index + 1]}"
			;;
		"--release")
			HELM_RELEASE="${ARGS[index + 1]}"
			;;
		"--engine")
			ENGINE="${ARGS[index + 1]}"
			;;
		"--gcp-project")
		    GCP_PROJECT="${ARGS[index + 1]}"
			;;
		"--extra")
		    EXTRA_CHECKS="true"
			;;
		"--*")
			_bad_arguments
			;;
		esac
	done

	# Check the common.names.fullname, we obtain this from https://github.com/bitnami/charts/blob/master/bitnami/common/templates/_names.tpl#L16-L32
	if [[ "${HELM_RELEASE}" == *"carto"* ]]; then
		CARTO_COMMON_FULLNAME="${HELM_RELEASE}"
	else CARTO_COMMON_FULLNAME="${HELM_RELEASE}"-carto
	fi

	# Check all mandatories args are passed by
	if [ -z "${NAMESPACE}" ] ||
		[ -z "${HELM_RELEASE}" ] ||
		[ -z "${ENGINE}" ]; then
		_bad_arguments
	fi

	_dump_info

	if [ "${EXTRA_CHECKS}" = "true" ]; then
	  _dump_extra_checks
	fi

	if [ "${ENGINE}" = "gke" ] && [ "${GCP_PROJECT}" != "" ]; then
	  _check_gke
	fi

	echo "Creating tar file..."
	tar -czvf "${DUMP_FOLDER}".tar.gz "${DUMP_FOLDER}" 2>>"${DUMP_FOLDER}"/error.log
}

_dump_info (){
	DUMP_FOLDER="${HELM_RELEASE}-${NAMESPACE}_$(date "+%Y.%m.%d-%H.%M.%S")"
	mkdir -p "${DUMP_FOLDER}"/pod

	echo "Downloading helm release info..."
	helm list -n "${NAMESPACE}" > "${DUMP_FOLDER}"/helm_release.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading pods..."
	kubectl get pods -n "${NAMESPACE}" -o wide -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/pods.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe pods -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/pods.out 2>>"${DUMP_FOLDER}"/error.log
	for POD in $(kubectl get pods -n "${NAMESPACE}" -o name -l app.kubernetes.io/instance="${HELM_RELEASE}"); \
	  do kubectl logs "${POD}" --all-containers -n "${NAMESPACE}" > "${DUMP_FOLDER}"/"${POD}".log 2>>"${DUMP_FOLDER}"/error.log; done

	echo "Downloading services..."
	kubectl get svc -n "${NAMESPACE}" -o wide -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/services.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe svc -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/services.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading endpoints..."
	kubectl get endpoints -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/endpoints.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe endpoints -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/endpoints.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading deployments..."
	kubectl get deployments -n "${NAMESPACE}" -o wide -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/deployments.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe deployments -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/deployments.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading ingress..."
	kubectl get ingress -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/ingress.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe ingress -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/ingress.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading BackendConfigs..."
	kubectl get backendconfigs -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/backendconfigs.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe backendconfigs -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/backendconfigs.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading FrontEndConfig..."
	kubectl get frontendconfigs -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/frontendconfigs.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe frontendconfigs -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/frontendconfigs.out 2>>"${DUMP_FOLDER}"/error.log

        # NOTE: k8s events are only kept for one hour by default, so it is desirable to run the carto-support-tool right after testing the installation
	echo "Downloading events..."
	kubectl get event -n "${NAMESPACE}" > "${DUMP_FOLDER}"/events.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading pvc..."
	kubectl get pvc -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/pvc.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe pvc -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/pvc.out 2>>"${DUMP_FOLDER}"/error.log

	echo "Downloading secrets info without passwords..."
	kubectl get secrets -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" > "${DUMP_FOLDER}"/secrets.out 2>>"${DUMP_FOLDER}"/error.log
	kubectl describe secrets -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" >> "${DUMP_FOLDER}"/secrets.out 2>>"${DUMP_FOLDER}"/error.log
}

_dump_extra_checks () {
	echo "Downloading cluster info..."
	kubectl cluster-info dump --namespaces="${NAMESPACE}" > "${DUMP_FOLDER}"/cluster_info.out 2>>"${DUMP_FOLDER}"/error.log
	echo "Checking Api health..."

	{
		echo "Checking Workspace API: "
		kubectl run "${HELM_RELEASE}"-check-workspace-api --image=curlimages/curl -n "${NAMESPACE}" --rm -i --tty --restart='Never' \
	    -- curl http://"${CARTO_COMMON_FULLNAME}"-workspace-api/health -H "Carto-Monitoring: true"
		echo "Checking Maps API: "
		kubectl run "${HELM_RELEASE}"-check-maps-api --image=curlimages/curl -n "${NAMESPACE}" --rm -i --tty --restart='Never' \
	    -- curl http://"${CARTO_COMMON_FULLNAME}"-maps-api/health -H "Carto-Monitoring: true"
		echo "Checking Import API: "
		kubectl run "${HELM_RELEASE}"-check-import-api --image=curlimages/curl -n "${NAMESPACE}" --rm -i --tty --restart='Never' \
	    -- curl http://"${CARTO_COMMON_FULLNAME}"-import-api/health -H "Carto-Monitoring: true"
	} >> "${DUMP_FOLDER}"/health_checks.out 2>>"${DUMP_FOLDER}"/error.log;
}


_check_gke () {
	echo "Check Ingress cert..."
	INGRESS_NAME=$(kubectl get ingress -n "${NAMESPACE}" -l app.kubernetes.io/instance="${HELM_RELEASE}" -o jsonpath='{.items[0].metadata.name}')
	SSL_CERT_ID=$(kubectl get ingress "${INGRESS_NAME}" -n "${NAMESPACE}" \
	  -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/ssl-cert}' 2>>"${DUMP_FOLDER}"/error.log)
    gcloud --project "${GCP_PROJECT}" compute ssl-certificates describe "${SSL_CERT_ID}" >> "${DUMP_FOLDER}"/ingress-ssl-cert.out 2>>"${DUMP_FOLDER}"/error.log
}

_main "$@"
