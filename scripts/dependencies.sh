#!/bin/bash -e

repo="quorum-acceptance-tests"

# expected versions
java_minimum_expected_version=14
terraform_expected_version=0.14.7
gauge_expected_version=1.3.3

## dependencies checker for local development
hash java 2>/dev/null || {
    echo >&2 "ERROR: java is required to run $repo"
    exit 1
}

hash terraform 2>/dev/null || {
    echo >&2 "ERROR: terraform is required to run $repo"
    exit 1
}

hash gauge 2>/dev/null || {
    echo >&2 "ERROR: gauge is required to run $repo"
    exit 1
}

string=$(terraform version | head -n 1)
pattern="[a-zA-Z ]+ v([0-9.]+)"
if [[ $string =~ $pattern ]]; then
    tf_version=${BASH_REMATCH[1]}
    echo "Terraform version found :: $tf_version"
    if [ $tf_version != $terraform_expected_version ]; then 
        echo >&2 "ERROR: invalid terraform version :: expects $terraform_expected_version"
        exit 1
    fi
    echo "Terraform version matched with expected"
fi

string=$(java --version | head -n 1)
pattern="([0-9.]+)"
if [[ $string =~ $pattern ]]; then
    java_version=${BASH_REMATCH[1]}
    major_version_pattern="([0-9]+).[0-9.]"
    [[ $java_version =~ $major_version_pattern ]]
    java_major_version=${BASH_REMATCH[1]}
    echo "Java version found :: $java_version"
    echo "Java major version found :: $java_major_version"
    if [ $java_major_version -lt $java_minimum_expected_version ]; then
        echo >&2 "ERROR: invalid java version :: expects minimum $java_minimum_expected_version"
        exit 1
    fi
fi

string=$(gauge --version | head -n 1)
pattern="([0-9.]+)"
if [[ $string =~ $pattern ]]; then
    gauge_version=${BASH_REMATCH[1]}
    echo "Gauge version found :: $gauge_version"
    if [ $gauge_version != $gauge_expected_version ]; then 
        echo >&2 "ERROR: invalid gauge version :: expects $gauge_expected_version"
        exit 1
    fi
    echo "Gauge version matched with expected"
fi

echo "All dependencies found"
