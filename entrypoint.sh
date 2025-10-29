#!/bin/bash -l

set -ue

EXTERNAL_DIC_DIR=cif-dictionaries

apt-get update

# Install 'subversion' since it is needed to retrieve the cod-tools package
apt-get -y install subversion

# Install 'moreutils' since it contain the 'sponge' program 
apt-get -y install moreutils

# Install 'git' since it is needed to retrieve the imported dictionaries
apt-get -y install git

# Make a sparse check out a fixed 'cod-tools' revision
COD_TOOLS_DIR=cod-tools
COD_TOOLS_REV=10048
mkdir ${COD_TOOLS_DIR}
cd ${COD_TOOLS_DIR}
svn co -r ${COD_TOOLS_REV} \
       --depth immediates \
       svn://www.crystallography.net/cod-tools/trunk .
svn up -r ${COD_TOOLS_REV} \
       --set-depth infinity \
       dependencies makefiles scripts src

# Install 'cod-tools' dependencies
apt-get -y install sudo
./dependencies/Ubuntu-22.04/build.sh
./dependencies/Ubuntu-22.04/run.sh

# Patch the Makefile and run custom build commands
# to avoid time-intensive tests
perl -pi -e 's/^(include \${DIFF_DEPEND})$/#$1/' \
    makefiles/Makefile-perl-multiscript-tests
make "$(pwd)"/src/lib/perl5/COD/CIF/Parser/Bison.pm
make "$(pwd)"/src/lib/perl5/COD/CIF/Parser/Yapp.pm
make ./src/lib/perl5/COD/ToolsVersion.pm

PERL5LIB=$(pwd)/src/lib/perl5${PERL5LIB:+:${PERL5LIB}}
export PERL5LIB
# shellcheck disable=SC2123
PATH=$(pwd)/scripts${PATH:+:${PATH}}
export PATH

cd ..

# Dictionary and template files in the tested repository
# should appear first in the import search path.
COD_TOOLS_DDLM_IMPORT_PATH=.

# Add external dictionaries to the import path.
if [ -d "${EXTERNAL_DIC_DIR}" ]
then
    for DIC_DIR in "${EXTERNAL_DIC_DIR}"/*
    do
        COD_TOOLS_DDLM_IMPORT_PATH="${COD_TOOLS_DDLM_IMPORT_PATH}:${DIC_DIR}"
        if [ -f "${DIC_DIR}"/ddl.dic ]
        then
            DDLM_REFERENCE_DIC=${DIC_DIR}/ddl.dic
        fi
    done
fi

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
# If these dictionaries are not part of the checked GitHub repository
# and they have not been provided as external dictionaries, then the
# latest available version from the COMCIFS/cif_core repository should
# be retrieved.

test -f ./ddl.dic && DDLM_REFERENCE_DIC=./ddl.dic

if [ ! -v DDLM_REFERENCE_DIC ]
then
    git clone https://github.com/COMCIFS/cif_core.git "${TMP_DIR}"/cif_core
    DDLM_REFERENCE_DIC="${TMP_DIR}"/cif_core/ddl.dic
    # Specify the location of imported files (e.g. "templ_attr.cif")
    COD_TOOLS_DDLM_IMPORT_PATH="$COD_TOOLS_DDLM_IMPORT_PATH:${TMP_DIR}/cif_core"
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
    #~      -e "ignored message A" \
    #~      -e "ignored message B" |
    #~ sponge "${OUT_FILE}"
    grep "${OUT_FILE}" -v -E \
         `# Data name from the imgCIF dictionary which cannot be renamed.` \
         `# See https://github.com/COMCIFS/Powder_Dictionary/pull/268` \
         -e "'_array_intensities[.]gain_su' instead of '_array_intensities[.]gain_esd'" \
         `# Primitive items with evaluation methods from the msCIF dictionary.` \
         `# These evaluation methods should be allowed since they do not perform ` \
         `# calculations, but only transform data structures.` \
         `# See https://github.com/COMCIFS/cif_core/pull/561` \
         -e "save_(reflns|diffrn_reflns)[.]limit_index_m_[1-9]_(min|max): .+ not contain evaluation" \
         -e "save_(refln|diffrn_refln|diffrn_standard_refln|exptl_crystal_face|twin_refln)[.]index_m_[1-9]: .+ not contain evaluation" \
         `# _type.dimension is provided in a dREL method` \
         -e "save_.+(q_coeff|global_phase_list|m_list|max_list|min_list|matrix_w).+ '_type.dimension' should be specified"
    | sponge "${OUT_FILE}"
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
    ddlm_validate \
        --follow-iucr-style-guide \
        --dictionaries "${DDLM_REFERENCE_DIC}" \
        "$file" > "${OUT_FILE}" 2> "${ERR_FILE}" || (
        echo "Execution of the 'ddlm_validate' script failed with" \
             "the following errors:"
        cat "${ERR_FILE}"
        rm -rf "${TMP_DIR}"
        exit 1
    )

    # Filter and report error messages
    #~ grep "${ERR_FILE}" -E -v \
    #~      -e "ignored message A" \
    #~      -e "regular expression matching ignored message B .*?" |
    #~ sponge "${ERR_FILE}"

    # Suppress warnings about dictionary attributes with the 'inherited'
    # type until this functionality gets properly implemented.
    grep "${ERR_FILE}" -v \
          -e "content type 'inherited' is not recognised" |
     sponge "${ERR_FILE}"
    
    if [ -s "${ERR_FILE}" ]
    then
        echo "Dictionary validation generated the following non-fatal errors:"
        cat "${ERR_FILE}"
    fi

    # Filter and report output messages
    #~ grep "${OUT_FILE}" -E -v \
    #~      -e "ignored message A" \
    #~      -e "regular expression matching ignored message B .*?" |
    #~ sponge "${OUT_FILE}"

    # Suppress warnings about missing dictionary DOI for now
    # (see discussion in https://github.com/COMCIFS/cif_core/pull/428).
    grep "${OUT_FILE}" -v \
         -e "data item '_dictionary.doi' is recommended" |
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
