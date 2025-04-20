#!/usr/bin/env bash

include './src/patch_track.sh'
include './tests/unit/utils.sh'

function oneTimeSetUp()
{
  declare -g DB_FILES

  export KW_ETC_DIR="${SHUNIT_TMPDIR}/etc/"
  export KW_CACHE_DIR="${SHUNIT_TMPDIR}/cache/"
  export KW_DATA_DIR="${SHUNIT_TMPDIR}"

  DB_FILES="$(realpath './tests/unit/samples/db_files')"
  KW_DB_DIR="$(realpath './database')"
}

function setUp()
{
  declare -gA options_values
  declare -gA set_confs

  setupDatabase
}

function tearDown()
{
  unset options_values
  unset set_confs

  tearDownDatabase
}

function setupDatabase()
{
  declare -g TEST_GROUP_NAME='TEST_GROUP'
  declare -g TEST_CONTACT_INFOS=('name' 'email')
  declare -g TEST_GROUP_ID

  execute_sql_script "${KW_DB_DIR}/kwdb.sql" > /dev/null 2>&1
  #sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO \"${DATABASE_TABLE_GROUP}\" (name) VALUES (\"${TEST_GROUP_NAME}\");"
  #TEST_GROUP_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM \"${DATABASE_TABLE_GROUP}\" WHERE name='${TEST_GROUP_NAME}';")"
  #sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO \"${DATABASE_TABLE_CONTACT}\" (name, email) VALUES (\"${TEST_CONTACT_INFOS[0]}\",\"${TEST_CONTACT_INFOS[1]}\");"
  #sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO \"${DATABASE_TABLE_CONTACT_GROUP}\" (contact_id, group_id) VALUES (1,1);"
}

function tearDownDatabase()
{
  is_safe_path_to_remove "${KW_DATA_DIR}/kw.db"
  if [[ "$?" == 0 ]]; then
    rm "${KW_DATA_DIR}/kw.db"
  fi
}

function test_register_patch_track()
{
  local expected
  local output
  local ret
  local _patches_titles

  # invalid values
  _patches_titles=('')
  output=$(register_patch_track _patches_titles)
  ret="$?"
  expected='Patch subject is empty'
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected an error' "$LINENO" "$ret" 61

  _patches_titles=("invalid_name'")
  output=$(register_patch_track _patches_titles 2> /dev/null)
  ret="$?"
  expected=$'Error while trying to insert patch into the database with the command:\n'
  expected+='sqlite3 -init /home/joao-souza/Mac0499---TCC/database/pre_cmd.sql "/tmp/shunit.tH1Kq2/tmp/kw.db"'
  expected+="-batch INSERT INTO patch (\"title\") VALUES ('invalid_name'');'"
  assertContains "$output" "$expected"
  assert_equals_helper 'Expected an error' "$LINENO" "$ret" 22

  # valid values
  _patches_titles=('valid_name')
  output=$(register_patch_track _patches_titles)
  ret="$?"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0
}

invoke_shunit
