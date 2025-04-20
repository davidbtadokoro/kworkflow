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
  declare -g TEST_PATCH_TITLE='TEST_PATCH'
  declare -g TEST_PATCH_ID

  execute_sql_script "${KW_DB_DIR}/kwdb.sql" > /dev/null 2>&1
  sqlite3 "${KW_DATA_DIR}/kw.db" -batch "INSERT INTO \"${DATABASE_PATCH_TABLE}\" (title) VALUES (\"${TEST_PATCH_TITLE}\");"
  TEST_PATCH_ID="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT id FROM \"${DATABASE_PATCH_TABLE}\" WHERE title='${TEST_PATCH_TITLE}';")"
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

function test_show_patches_dashboard()
{
  local expected
  local output
  local ret
  local patch_info
  local IFS

  # valid values
  patch_info="$(sqlite3 "${KW_DATA_DIR}/kw.db" -batch "SELECT * FROM \"${DATABASE_PATCH_TABLE}\" WHERE title = (\"${TEST_PATCH_TITLE}\");")"
  IFS='|' read -r id date time status title <<< "$patch_info"

  output=$(show_patches_dashboard '' 150)
  ret="$?"

  expected+=$'ID    |Date        |Time      |Status    |Title\n'
  expected+=$'------------------------------------------------------------------------------------------------------------------------------------------------------\n'
  expected+="${id}     |${date}  |${time}  |${status}      |${title}"
  expected+=$'\n'
  expected+=$'------------------------------------------------------------------------------------------------------------------------------------------------------'
  assert_equals_helper 'Empty group should not be valid' "$LINENO" "$expected" "$output"
  assert_equals_helper 'Expected no error' "$LINENO" "$ret" 0
}

invoke_shunit
