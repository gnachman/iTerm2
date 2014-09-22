#!/bin/bash

MASTER_DIR=`pwd`
MASTER="English.lproj"
LOCALIZATIONS=`ls | fgrep lproj`


for LANGUAGE in $LOCALIZATIONS
do
	if [[ -d $LANGUAGE && $LANGUAGE != $MASTER ]]; then
		echo -e "\nProcessing $LANGUAGE localization"
		cd $LANGUAGE

		NIB_DICTS=`ls *.strings`

		for DICT in $NIB_DICTS
		do
			NIB_FILE=`echo -n $DICT | awk -F "." '{print $1}'`.nib
			# If the master nib file exists, translate it
			if [ -d ${MASTER_DIR}/${MASTER}/${NIB_FILE} ]; then

				echo "Translating ${NIB_FILE}"
				TEMP_NIB_FILE=tmp.nib

				# Check if the target nib file already exists
				if [ -d ${NIB_FILE} ]; then
					nibtool -I ${NIB_FILE} -w ${TEMP_NIB_FILE} -d ${DICT} ${MASTER_DIR}/${MASTER}/${NIB_FILE}
					cp ${TEMP_NIB_FILE}/* ${NIB_FILE}
					rm -rf ${TEMP_NIB_FILE}
				else
					nibtool -w ${TEMP_NIB_FILE} -d ${DICT} ${MASTER_DIR}/${MASTER}/${NIB_FILE}
					mv ${TEMP_NIB_FILE} ${NIB_FILE}
				fi
			
			fi
		done

		cd $MASTER_DIR

	fi
done
