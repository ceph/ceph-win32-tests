function get_instance_state() {
    local INSTANCE_ID=$1
    ensure_vars_set INSTANCE_ID
    nova show $INSTANCE_ID | grep " status  " | awk '{print $4}'
}

function wait_for_instance_state () {
    local INSTANCE_ID=$1
    local EXPECTED_STATE=$2
    local TIMEOUT=${3:-180}
    local POLL_INTERVAL=${4:-2}
    local INSTANCE_STATE

    SECONDS=0
    TRIES=0

    required_vars=(INSTANCE_ID EXPECTED_STATE TIMEOUT POLL_INTERVAL)
    ensure_vars_set $required_vars

    INSTANCE_STATE=$(get_instance_state $INSTANCE_ID)

    while [[ $SECONDS -lt $TIMEOUT ]] && \
            [[ ! ( ${INSTANCE_STATE^^} =~ "ERROR" \
                || $INSTANCE_STATE == $EXPECTED_STATE ) ]]; do

        sleep $POLL_INTERVAL
        INSTANCE_STATE=$(get_instance_state $INSTANCE_ID)
    done

    if [[ ${INSTANCE_STATE^^} =~ "ERROR" ]]; then
        nova show $INSTANCE_ID
        log_summary "Instance $INSTANCE_ID entered error state"\
                    "($INSTANCE_STATE)."
        return 1
    fi

    if [[ $INSTANCE_STATE != $EXPECTED_STATE ]]; then
        log_summary "Timeout ($SECONDS s) waiting for instance" \
                    "$INSTANCE_ID to become $EXPECTED_STATE." \
                    "Current state: $INSTANCE_STATE."
        return 1
    else
        log_summary "Instance $INSTANCE_ID reached expected" \
                    "state: $INSTANCE_STATE."
    fi
}

function wait_for_instance_boot () {
    local INSTANCE_ID=$1
    local TIMEOUT=${2:-180}
    local POLL_INTERVAL=${3:-2}

    required_vars=(INSTANCE_ID EXPECTED_STATE TIMEOUT POLL_INTERVAL)
    ensure_vars_set $required_vars

    wait_for_instance_state $INSTANCE_ID "ACTIVE" $TIMEOUT $POLL_INTERVAL
}

function boot_vm() {
    # This function doesn't wait for the instance to spawn, call
    # 'wait_for_instance_boot' after booting the vm.
    local VMID
    local _ERR_OPTS

    _ERR_OPTS=$(set +o | grep err)
    set +eE

    VMID=$(nova boot $@ | grep " id " | cut -d "|" -f 3)

    local NOVABOOT_EXIT=$?
    $_ERR_OPTS

    if [ $NOVABOOT_EXIT -ne 0 ]; then
        nova show "$VMID"
        nova delete $VMID
        log_summary "Failed to create VM: $VMID"
        return 1
    fi
    echo $VMID
}

function get_vm_ip() {
    local vmName=$1
    local vms
    local vmCount
    vms=`nova list | grep $vmName`
    vmCount=`echo $vms | wc -l`

    if [[ -z $vms ]]; then
        log_summary "Could not find vm $vmName."
        return 1
    fi

    if [[ $vmCount -gt 1 ]]; then
        log_summary "Found multiple vms."
        return 1
    fi

    local ip
    ip=`echo $vms | cut -d '|' -f 7 | sed -r 's/.*=//'`
    if [[ -z $ip ]]; then
        log_summary "Failed to retrieve vm \"$vmName\" ip."
        return 1;
    fi

    echo $ip
}

function delete_vm_if_exists() {
    local VM_ID=$1

    if [[ -z $VM_ID ]]; then
        log_summary "No vm id specified. Skipping delete."
    fi

    if [[ $(nova list | grep $VM_ID) ]]; then
        log_summary "Deleting vm $VM_ID"
        nova delete $VM_ID
    else
        log_summary "VM $VM_ID does not exist. Skipping delete."
    fi
}
