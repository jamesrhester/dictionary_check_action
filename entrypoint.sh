#!/bin/bash -l

set -ue

# get latest cod-tools

apt-get update

apt-get -y install cod-tools

# install 'moreutils' since it contain the 'sponge' program 

apt-get -y install moreutils

# install 'git' since it is needed to retrieve the imported dictionaries

apt-get -y install git

# Prepare dictionaries and template files that may be
# required to properly validate other dictionaries
TMP_DIR=$(mktemp -d)

# Prepare the DDLm reference dictionary and the CIF_CORE dictionary.
#
# If these dictionaries are part of the checked GitHub repository,
# then the local copies should be used to ensure self-consistency,
# e.g. the latest version of the reference dictionary should validate
# against itself. This scenario will most likely only occur in the
# COMCIFS/cif_core repository. 
#
# If these dictionaries are not part of the checked GitHub repository,
# then the latest available version from the COMCIFS/cif_core repository
# should be retrieved.

DDLM_REFERENCE_DIC=./ddl.dic
if [ ! -f "${DDLM_REFERENCE_DIC}" ]
then
    git clone https://github.com/COMCIFS/cif_core.git "${TMP_DIR}"/cif_core
    DDLM_REFERENCE_DIC="${TMP_DIR}"/cif_core/ddl.dic
    # Specify the location of imported files (i.e. "templ_attr.cif")
    COD_TOOLS_DDLM_IMPORT_PATH="${TMP_DIR}"/cif_core
fi
export COD_TOOLS_DDLM_IMPORT_PATH 

# run the checks
shopt -s nullglob

# Check dictionaries for stylistic and semantic issues
OUT_FILE="${TMP_DIR}/cif_ddlm_dic_check.out"
ERR_FILE="${TMP_DIR}/cif_ddlm_dic_check.err"
for file in ./*.dic
do
    # Run the checks and report fatal errors
    cif_ddlm_dic_check "$file" > "${OUT_FILE}" 2> "${ERR_FILE}" || (
        echo "Execution of the 'cif_ddlm_dic_check' script failed with" \
             "the following errors:"
        cat "${ERR_FILE}"
        rm -rf "${TMP_DIR}"
        exit 1
    )

    # Filter and report error messages
    #~ grep "${ERR_FILE}" -v \
    #~      -e "ignored message A" \
    #~      -e "ignored message B" |
    #~ sponge "${ERR_FILE}"
    if [ -s "${ERR_FILE}" ]
    then
        echo "Dictionary check generated the following non-fatal errors:"
        cat "${ERR_FILE}"
    fi

    # Filter and report output messages
    #~ grep "${OUT_FILE}" -v \
    #~     -e "ignored message A" \
    #~     -e "ignored message B" |
    #~ sponge "${OUT_FILE}"
    if [ -s "${OUT_FILE}" ]
    then
        echo "Dictionary check detected the following irregularities:";
        cat "${OUT_FILE}"
        rm -rf "${TMP_DIR}"
        exit 1
    fi
done

# Validate dictionaries against the DDLm reference dictionary
OUT_FILE="${TMP_DIR}/ddlm_validate.out"
ERR_FILE="${TMP_DIR}/ddlm_validate.err"
for file in ./*.dic
do
    ddlm_validate --dictionaries "${DDLM_REFERENCE_DIC}" \
        "$file" > "${OUT_FILE}" 2> "${ERR_FILE}" || (
        echo "Execution of the 'ddlm_validate' script failed with" \
             "the following errors:"
        cat "${ERR_FILE}"
        rm -rf "${TMP_DIR}"
        exit 1
    )

    # Filter and report error messages
    #~ grep "${ERR_FILE}" -v \
    #~      -e "ignored message A" \
    #~      -e "ignored message B" |
    #~ sponge "${ERR_FILE}"
    if [ -s "${ERR_FILE}" ]
    then
        echo "Dictionary validation generated the following non-fatal errors:"
        cat "${ERR_FILE}"
    fi

    # Filter and report output messages
    grep "${OUT_FILE}" -P -v \
         -e "is recommended in the .*? scope" \
         -e "data item '_description_example.case' value" |
    sponge "${OUT_FILE}"
    if [ -s "${OUT_FILE}" ]
    then
        echo "Dictionary validation detected the following validation issues:";
        cat "${OUT_FILE}"
        rm -rf "${TMP_DIR}"
        exit 1
    fi
done
rm -rf "${TMP_DIR}"
