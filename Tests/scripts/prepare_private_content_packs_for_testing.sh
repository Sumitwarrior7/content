#!/usr/bin/env bash

# exit on errors
set -e

GIT_BRANCH=${BRANCH_NAME:-unknown}
GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER:-00000}
PACK_ARTIFACTS=$ARTIFACTS_FOLDER/content_packs.zip
EXTRACT_FOLDER=$(mktemp -d)

if [[ -z "$GCS_MARKET_KEY" ]]; then
    echo "GCS_MARKET_KEY not set aborting!"
    exit 1
fi

echo "Preparing content packs for testing ..."

KF=$(mktemp)
echo "$GCS_MARKET_KEY" > "$KF"
mkdir -p "${ARTIFACTS_FOLDER}/logs/"
gcloud auth activate-service-account --key-file="$KF" >> "${ARTIFACTS_FOLDER}/logs/gcloud_auth.log" 2>&1
echo "Auth loaded successfully."

GCS_MARKET_BUCKET="${TEST_XDR_PREFIX}marketplace-dist"
GCS_BUILD_BUCKET="${TEST_XDR_PREFIX}marketplace-ci-build-private"


GCS_PRIVATE_TESTING_BUCKET="${TEST_XDR_PREFIX}marketplace-ci-build-private"
GCS_PRIVATE_PROD_BUCKET="${TEST_XDR_PREFIX}marketplace-dist-private"
GCS_TESTING_BUCKET="${TEST_XDR_PREFIX}marketplace-ci-build"
GCS_PUBLIC_PROD_BUCKET="${TEST_XDR_PREFIX}marketplace-dist"
SOURCE_PATH="content/packs"

PRIVATE_BUILD_BUCKET_PATH="content/builds/$GIT_BRANCH/$GITHUB_RUN_NUMBER"
PRIVATE_TARGET_PATH="$PRIVATE_BUILD_BUCKET_PATH/content/packs"
BUCKET_FULL_TARGET_PATH="$GCS_PRIVATE_TESTING_BUCKET/$PRIVATE_BUILD_BUCKET_PATH"

echo "Copying private master files at: $SOURCE_PATH to target path: gs://$GCS_PRIVATE_TESTING_BUCKET/$PRIVATE_TARGET_PATH ..."
gsutil -m cp -r "gs://$GCS_PRIVATE_PROD_BUCKET/$SOURCE_PATH" "gs://$GCS_PRIVATE_TESTING_BUCKET/$PRIVATE_TARGET_PATH"
echo "Finished copying private bucket successfully."


echo "Copying index.zip at: gs://${TEST_XDR_PREFIX}marketplace-dist/content/packs/index.zip to target path: gs://marketplace-ci-build/private/dummy_index/index.zip ..."
gsutil -m cp "gs://${TEST_XDR_PREFIX}marketplace-dist/content/packs/index.zip" "gs://marketplace-ci-build/private/dummy_index/index.zip"
echo "Finished copying private index.zip successfully."


PUBLIC_BUILD_BUCKET_PATH="content/builds/$GIT_BRANCH/$GITHUB_RUN_NUMBER"
PUBLIC_TARGET_PATH="$PUBLIC_BUILD_BUCKET_PATH/content/packs"
BUCKET_FULL_TARGET_PATH="$GCS_TESTING_BUCKET/$PUBLIC_BUILD_BUCKET_PATH"

echo "Copying public master files at: $SOURCE_PATH to target path: gs://$GCS_TESTING_BUCKET/$PUBLIC_TARGET_PATH ..."
gsutil -m cp -r "gs://$GCS_PUBLIC_PROD_BUCKET/$SOURCE_PATH" "gs://$GCS_TESTING_BUCKET/$PUBLIC_TARGET_PATH"
echo "Finished copying public bucket successfully."

echo "Updating modified content packs in the bucket ..."


CONTENT_PACKS_TO_INSTALL_FILE="$ARTIFACTS_FOLDER/content_packs_to_install.txt"
if [ ! -f $CONTENT_PACKS_TO_INSTALL_FILE ]; then
  echo "Could not find file $CONTENT_PACKS_TO_INSTALL_FILE."
else
  CONTENT_PACKS_TO_INSTALL=$(paste -sd, $CONTENT_PACKS_TO_INSTALL_FILE)
  if [[ -z "$CONTENT_PACKS_TO_INSTALL" ]]; then
    echo "Did not get content packs to update in the bucket."
  else
    echo "Updating the following content packs: $CONTENT_PACKS_TO_INSTALL ..."
    python3 ./Tests/private_build/upload_packs_private.py -b $GCS_TESTING_BUCKET -pb $GCS_PRIVATE_TESTING_BUCKET -a $PACK_ARTIFACTS -d $ARTIFACTS_FOLDER/packs_dependencies.json -e $EXTRACT_FOLDER -s $KF -n $GITHUB_RUN_NUMBER -p $NEW_PACK_NAME -sb $PUBLIC_TARGET_PATH -k $PACK_SIGN_KEY -rt false -nek $PACK_ENCRYPTION_KEY_NEW -bn $GIT_BRANCH -ek $PACK_ENCRYPTION_KEY -inf $IS_INFRA_BUILD -o
    NEW_EXTRACT_FOLDER_FOR_INDEX=$(mktemp -d)
    NEW_EXTRACT_FOLDER_FOR_ARTIFACTS=$(mktemp -d)
    echo "\nbetween the two scripts\n"
    python3 ./Tests/Marketplace/prepare_public_index_for_private_testing.py -b $GCS_TESTING_BUCKET -pb $GCS_PRIVATE_TESTING_BUCKET -n $GITHUB_RUN_NUMBER -e $NEW_EXTRACT_FOLDER_FOR_INDEX -sb $PUBLIC_TARGET_PATH -s $KF -p $NEW_PACK_NAME -a $PACK_ARTIFACTS -ea $NEW_EXTRACT_FOLDER_FOR_ARTIFACTS -di private/dummy_index
    echo "Finished updating content packs successfully."
  fi
fi


#echo "Normalizing images paths to build bucket ..."
#python3 ./Tests/Marketplace/normalize_gcs_paths.py -sb $TARGET_PATH -b $GCS_BUILD_BUCKET -s $KF
#echo "Finished normalizing images paths successfully."

BUCKET_FULL_TARGET_PATH="$GCS_PRIVATE_TESTING_BUCKET/$PRIVATE_BUILD_BUCKET_PATH"

echo -e "\nBrowse to the build bucket with this address:"
echo -e "https://console.cloud.google.com/storage/browser/$BUCKET_FULL_TARGET_PATH\n"
echo "Finished preparing content packs for testing successfully."

echo -e "\nIf you want to connect this build bucket to your test machine, add this server configs:"
echo "marketplace.bootstrap.bypass.url: https://storage.googleapis.com/$BUCKET_FULL_TARGET_PATH"
echo "jobs.marketplacepacks.schedule: 1m"
