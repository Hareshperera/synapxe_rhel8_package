#!/bin/bash

# Import base test framework
source "$(dirname "$0")/base_test.sh"

# SELinux test cases
test_selinux() {
    # Inherit from base test class
    class_test
    
    setup() {
        # Backup SELinux config
        if [ -f "/etc/selinux/config" ]; then
            cp "/etc/selinux/config" "/etc/selinux/config.bak"
        fi
    }
    
    teardown() {
        # Restore SELinux config
        if [ -f "/etc/selinux/config.bak" ]; then
            mv "/etc/selinux/config.bak" "/etc/selinux/config"
        fi
    }
    
    test_selinux_enabled() {
        local status=$(getenforce)
        assert_equals "Enforcing" "$status" "SELinux is not in enforcing mode"
    }
    
    test_selinux_config() {
        local config_mode=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
        assert_equals "enforcing" "$config_mode" "SELinux config is not set to enforcing"
    }
    
    test_selinux_tools() {
        # Check if required tools are installed
        local tools=("semanage" "setsebool" "getsebool")
        for tool in "${tools[@]}"; do
            command -v "$tool" >/dev/null 2>&1 || {
                log "SELinux tool $tool is not installed" "FAIL"
                return $TEST_FAIL
            }
        done
        return $TEST_PASS
    }
    
    test_selinux_booleans() {
        # Check critical SELinux booleans
        local booleans=(
            "httpd_enable_cgi=off"
            "httpd_can_network_connect=off"
            "ftp_home_dir=off"
        )
        
        for boolean in "${booleans[@]}"; do
            local name=${boolean%=*}
            local expected_value=${boolean#*=}
            local actual_value=$(getsebool -a | grep "^$name " | cut -d" " -f3)
            
            assert_equals "$expected_value" "$actual_value" "SELinux boolean $name has incorrect value"
        done
    }
    
    # Run all SELinux tests
    run_selinux_tests() {
        local tests=(
            test_selinux_enabled
            test_selinux_config
            test_selinux_tools
            test_selinux_booleans
        )
        
        for test in "${tests[@]}"; do
            run_test "selinux_$test" "$test"
        done
    }
}

# Initialize and run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_selinux
    run_selinux_tests
fi 