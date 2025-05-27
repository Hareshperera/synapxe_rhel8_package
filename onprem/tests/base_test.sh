#!/bin/bash

# Base test framework for Synapxe RHEL 8 Audit

# Test result codes
TEST_PASS=0
TEST_FAIL=1
TEST_SKIP=2

# Test metadata
declare -A TEST_METADATA=(
    ["test_selinux"]="severity=HIGH category=SECURITY"
    ["test_firewall"]="severity=HIGH category=NETWORK"
    ["test_permissions"]="severity=MEDIUM category=FILESYSTEM"
)

# Base test class
class_test() {
    setup() {
        # Override in specific tests
        return 0
    }
    
    teardown() {
        # Override in specific tests
        return 0
    }
    
    skip_test() {
        local test_name=$1
        [[ " ${SKIP_TESTS[@]} " =~ " $test_name " ]]
    }
    
    run_test() {
        local test_name=$1
        local test_func=$2
        
        if skip_test "$test_name"; then
            log "Skipping test: $test_name" "INFO"
            return $TEST_SKIP
        fi
        
        setup
        local result=$($test_func)
        local status=$?
        teardown
        
        return $status
    }
    
    assert_equals() {
        local expected=$1
        local actual=$2
        local message=${3:-"Values do not match"}
        
        if [ "$expected" = "$actual" ]; then
            return $TEST_PASS
        else
            log "$message (Expected: $expected, Got: $actual)" "FAIL"
            return $TEST_FAIL
        fi
    }
    
    assert_file_exists() {
        local file=$1
        local message=${2:-"File does not exist: $file"}
        
        if [ -f "$file" ]; then
            return $TEST_PASS
        else
            log "$message" "FAIL"
            return $TEST_FAIL
        fi
    }
    
    assert_directory_exists() {
        local dir=$1
        local message=${2:-"Directory does not exist: $dir"}
        
        if [ -d "$dir" ]; then
            return $TEST_PASS
        else
            log "$message" "FAIL"
            return $TEST_FAIL
        fi
    }
    
    assert_permission() {
        local path=$1
        local expected_perm=$2
        local message=${3:-"Incorrect permissions"}
        
        local actual_perm=$(stat -c "%a" "$path")
        if [ "$actual_perm" = "$expected_perm" ]; then
            return $TEST_PASS
        else
            log "$message (Expected: $expected_perm, Got: $actual_perm)" "FAIL"
            return $TEST_FAIL
        fi
    }
}

# Export the test class
export -f class_test 