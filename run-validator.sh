        if ! timeout ${TONOS_CLI_TIMEOUT} "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
            "{\"dest\":\"${DEPOOL_ADDR}\",\"value\":\"1000000000\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
            --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
            --sign "${KEYS_DIR}/msig.keys.json"; then
            echo "INFO: tonos-cli submitTransaction attempt... FAIL"
            exit_and_clean 1 $LINENO
        else
            echo "INFO: tonos-cli submitTransaction attempt... PASS"
            date +"INFO: %F %T prepared for elections ${ACTIVE_ELECTION_ID}"
            echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"
        fi
        set +x
    else
        if [ -z "${STAKE}" ]; then
            echo "INFO: dynamic staking mode"
            if [ ! -f "${VALIDATOR_INIT_BALANCE_FILE}" ]; then
                echo "${VALIDATOR_ACTUAL_BALANCE}" >"${VALIDATOR_INIT_BALANCE_FILE}"
                # Split actual balance for 2 election cycles
                STAKE=$(((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER) / 2))
            else
                if [ ${VALIDATOR_ACTUAL_BALANCE} = "$(cat "${VALIDATOR_INIT_BALANCE_FILE}")" ]; then
                    # 1st stake has not yet been submitted
                    # Split actual balance for 2 election cycles
                    STAKE=$(((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER) / 2))
                else
                    # It is 2nd (and further) staking iteration - use all available tokens (except the reminder for fees)
                    STAKE=$((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER))
                fi
            fi
        else
            echo "INFO: fixed staking mode"
        fi

        echo "INFO: STAKE = $STAKE tokens"

        if [ $STAKE -ge ${VALIDATOR_ACTUAL_BALANCE} ]; then
            echo "ERROR: not enough tokens in ${MSIG_ADDR} wallet"
            echo "INFO: VALIDATOR_ACTUAL_BALANCE = ${VALIDATOR_ACTUAL_BALANCE}"
            exit_and_clean 1 $LINENO
        fi

        TONOS_CLI_OUTPUT=$(${UTILS_DIR}/tonos-cli getconfig 17)
        MIN_STAKE=$(echo "${TONOS_CLI_OUTPUT}" | awk '/min_stake/ {print $2}' | tr -d '"' | tr -d ',') # in nanotokens
        MIN_STAKE=$((MIN_STAKE / 1000000000))                                                          # in tokens
        echo "INFO: MIN_STAKE = ${MIN_STAKE} tokens"

        if [ -z "${MIN_STAKE}" ]; then
            echo "ERROR: MIN_STAKE is empty"
            exit_and_clean 1 $LINENO
        fi

        if [ "$STAKE" -lt "${MIN_STAKE}" ]; then
            echo "ERROR: STAKE ($STAKE tokens) is less than MIN_STAKE (${MIN_STAKE} tokens)"
            exit_and_clean 1 $LINENO
        fi

        NANOSTAKE=$((STAKE * 1000000000))
        echo "INFO: NANOSTAKE = $NANOSTAKE nanotokens"

        if [ -z "${NANOSTAKE}" ]; then
            echo "ERROR: NANOSTAKE is empty"
            exit_and_clean 1 $LINENO
        fi

        set -x
        case ${VALIDATOR_TYPE} in
        "sdk")
            echo "INFO: tonos-cli submitTransaction attempt..."
            if ! timeout ${TONOS_CLI_TIMEOUT} "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
                "{\"dest\":\"${ELECTOR_ADDR}\",\"value\":\"${NANOSTAKE}\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
                --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
                --sign "${KEYS_DIR}/msig.keys.json"; then
                echo "INFO: tonos-cli submitTransaction attempt... FAIL"
                exit_and_clean 1 $LINENO
            else
                echo "INFO: tonos-cli submitTransaction attempt... PASS"
            fi
            ;;
        "console")
            if ! "${UTILS_DIR}/tonos-cli" message "${MSIG_ADDR}" submitTransaction \
                "{\"dest\":\"${ELECTOR_ADDR}\",\"value\":\"${NANOSTAKE}\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
                --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
                --sign "${KEYS_DIR}/msig.keys.json" \
                --raw --output "${ELECTIONS_WORK_DIR}/validator_query_msg.boc"; then
                exit_and_clean 1 $LINENO
            else
                if [ ! -f "${ELECTIONS_WORK_DIR}/validator_query_msg.boc" ]; then
                    echo "ERROR: ${ELECTIONS_WORK_DIR}/validator_query_msg.boc does not exist"
                    exit_and_clean 1 $LINENO
                fi
                if ! ${UTILS_DIR}/console -C ${CONFIGS_DIR}/console.json -c "sendmessage ${ELECTIONS_WORK_DIR}/validator_query_msg.boc"; then
                    echo "ERROR: console sendmessage ${ELECTIONS_WORK_DIR}/validator_query_msg.boc failed"
                    exit_and_clean 1 $LINENO
                fi

                sleep ${BLOCKCHAIN_TIMEOUT}

                CONSOLE_OUTPUT=$(${UTILS_DIR}/console -C ${CONFIGS_DIR}/console.json -j -c "getaccount ${MSIG_ADDR}")
                VALIDATOR_NEW_BALANCE_NANO=$(echo "${CONSOLE_OUTPUT}" | jq -r '.balance')
                VALIDATOR_BALANCE_DIFF=$((VALIDATOR_ACTUAL_BALANCE_NANO - VALIDATOR_NEW_BALANCE_NANO))

                # 10000 tokens - minimal stake
                if [ ${VALIDATOR_BALANCE_DIFF} -lt "10000000000000" ]; then
                    echo "ERROR: stake was not delivered"
                    exit_and_clean 1 $LINENO
                fi
            fi
            ;;
        esac
        set +x
        sleep 10
        date +"INFO: %F %T prepared for elections ${ACTIVE_ELECTION_ID}"
        echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"
    fi
}

#==============================================================================
#                                Main
#==============================================================================
init_env
check_env
if [ "${DEPOOL_ENABLE}" != "yes" ]; then
    recover_stake
fi
prepare_for_elections
create_elector_request
submit_stake
exit_and_clean 0 $LINENO        if ! timeout ${TONOS_CLI_TIMEOUT} "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
            "{\"dest\":\"${DEPOOL_ADDR}\",\"value\":\"1000000000\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
            --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
            --sign "${KEYS_DIR}/msig.keys.json"; then
            echo "INFO: tonos-cli submitTransaction attempt... FAIL"
            exit_and_clean 1 $LINENO
        else
            echo "INFO: tonos-cli submitTransaction attempt... PASS"
            date +"INFO: %F %T prepared for elections ${ACTIVE_ELECTION_ID}"
            echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"
        fi
        set +x
    else
        if [ -z "${STAKE}" ]; then
            echo "INFO: dynamic staking mode"
            if [ ! -f "${VALIDATOR_INIT_BALANCE_FILE}" ]; then
                echo "${VALIDATOR_ACTUAL_BALANCE}" >"${VALIDATOR_INIT_BALANCE_FILE}"
                # Split actual balance for 2 election cycles
                STAKE=$(((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER) / 2))
            else
                if [ ${VALIDATOR_ACTUAL_BALANCE} = "$(cat "${VALIDATOR_INIT_BALANCE_FILE}")" ]; then
                    # 1st stake has not yet been submitted
                    # Split actual balance for 2 election cycles
                    STAKE=$(((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER) / 2))
                else
                    # It is 2nd (and further) staking iteration - use all available tokens (except the reminder for fees)
                    STAKE=$((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER))
                fi
            fi
        else
            echo "INFO: fixed staking mode"
        fi

        echo "INFO: STAKE = $STAKE tokens"

        if [ $STAKE -ge ${VALIDATOR_ACTUAL_BALANCE} ]; then
            echo "ERROR: not enough tokens in ${MSIG_ADDR} wallet"
            echo "INFO: VALIDATOR_ACTUAL_BALANCE = ${VALIDATOR_ACTUAL_BALANCE}"
            exit_and_clean 1 $LINENO
        fi

        TONOS_CLI_OUTPUT=$(${UTILS_DIR}/tonos-cli getconfig 17)
        MIN_STAKE=$(echo "${TONOS_CLI_OUTPUT}" | awk '/min_stake/ {print $2}' | tr -d '"' | tr -d ',') # in nanotokens
        MIN_STAKE=$((MIN_STAKE / 1000000000))                                                          # in tokens
        echo "INFO: MIN_STAKE = ${MIN_STAKE} tokens"

        if [ -z "${MIN_STAKE}" ]; then
            echo "ERROR: MIN_STAKE is empty"
            exit_and_clean 1 $LINENO
        fi

        if [ "$STAKE" -lt "${MIN_STAKE}" ]; then
            echo "ERROR: STAKE ($STAKE tokens) is less than MIN_STAKE (${MIN_STAKE} tokens)"
            exit_and_clean 1 $LINENO
        fi

        NANOSTAKE=$((STAKE * 1000000000))
        echo "INFO: NANOSTAKE = $NANOSTAKE nanotokens"

        if [ -z "${NANOSTAKE}" ]; then
            echo "ERROR: NANOSTAKE is empty"
            exit_and_clean 1 $LINENO
        fi

        set -x
        case ${VALIDATOR_TYPE} in
        "sdk")
            echo "INFO: tonos-cli submitTransaction attempt..."
            if ! timeout ${TONOS_CLI_TIMEOUT} "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
                "{\"dest\":\"${ELECTOR_ADDR}\",\"value\":\"${NANOSTAKE}\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
                --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
                --sign "${KEYS_DIR}/msig.keys.json"; then
                echo "INFO: tonos-cli submitTransaction attempt... FAIL"
                exit_and_clean 1 $LINENO
            else
                echo "INFO: tonos-cli submitTransaction attempt... PASS"
            fi
            ;;
        "console")
            if ! "${UTILS_DIR}/tonos-cli" message "${MSIG_ADDR}" submitTransaction \
                "{\"dest\":\"${ELECTOR_ADDR}\",\"value\":\"${NANOSTAKE}\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
                --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
                --sign "${KEYS_DIR}/msig.keys.json" \
                --raw --output "${ELECTIONS_WORK_DIR}/validator_query_msg.boc"; then
                exit_and_clean 1 $LINENO
            else
                if [ ! -f "${ELECTIONS_WORK_DIR}/validator_query_msg.boc" ]; then
                    echo "ERROR: ${ELECTIONS_WORK_DIR}/validator_query_msg.boc does not exist"
                    exit_and_clean 1 $LINENO
                fi
                if ! ${UTILS_DIR}/console -C ${CONFIGS_DIR}/console.json -c "sendmessage ${ELECTIONS_WORK_DIR}/validator_query_msg.boc"; then
                    echo "ERROR: console sendmessage ${ELECTIONS_WORK_DIR}/validator_query_msg.boc failed"
                    exit_and_clean 1 $LINENO
                fi

                sleep ${BLOCKCHAIN_TIMEOUT}

                CONSOLE_OUTPUT=$(${UTILS_DIR}/console -C ${CONFIGS_DIR}/console.json -j -c "getaccount ${MSIG_ADDR}")
                VALIDATOR_NEW_BALANCE_NANO=$(echo "${CONSOLE_OUTPUT}" | jq -r '.balance')
                VALIDATOR_BALANCE_DIFF=$((VALIDATOR_ACTUAL_BALANCE_NANO - VALIDATOR_NEW_BALANCE_NANO))

                # 10000 tokens - minimal stake
                if [ ${VALIDATOR_BALANCE_DIFF} -lt "10000000000000" ]; then
                    echo "ERROR: stake was not delivered"
                    exit_and_clean 1 $LINENO
                fi
            fi
            ;;
        esac
        set +x
        sleep 10
        date +"INFO: %F %T prepared for elections ${ACTIVE_ELECTION_ID}"
        echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"
    fi
}

#==============================================================================
#                                Main
#==============================================================================
init_env
check_env
if [ "${DEPOOL_ENABLE}" != "yes" ]; then
    recover_stake
fi
prepare_for_elections
create_elector_request
submit_stake
exit_and_clean 0 $LINENO
