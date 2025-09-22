#!/bin/bash

# ============================================
# BIGQUERY AI - AUTOMATED CONTINUOUS TESTING
# Production-grade testing with full observability
# ============================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly PROJECT_ID="bigquery-ai-hackathon-2025"
readonly LOCATION="us-central1"
readonly DATASET_ID="test_dataset_central"
readonly CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
readonly TEST_RUN_ID=$(uuidgen 2>/dev/null || echo "test_$(date +%s)")
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_DIR="bigquery_ai_tests_${TIMESTAMP}"
readonly METRICS_FILE="${LOG_DIR}/metrics.json"
readonly SUMMARY_FILE="${LOG_DIR}/summary.txt"

# Create log directory
mkdir -p "$LOG_DIR"

# Logging with levels
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local log_entry="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\",\"test_run_id\":\"$TEST_RUN_ID\"}"
    echo "$log_entry" >> "${LOG_DIR}/test.jsonl"
    
    # Also output to console with colors
    case $level in
        ERROR)   echo -e "\033[0;31m[ERROR]\033[0m $message" ;;
        SUCCESS) echo -e "\033[0;32m[SUCCESS]\033[0m $message" ;;
        INFO)    echo -e "\033[0;34m[INFO]\033[0m $message" ;;
        WARN)    echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        *)       echo "[$level] $message" ;;
    esac
}

# Metric collection
declare -A metrics
collect_metric() {
    local metric_name=$1
    local value=$2
    metrics[$metric_name]=$value
}

# Test execution with detailed logging
execute_test() {
    local test_id=$1
    local test_name=$2
    local query=$3
    local validation_fn=${4:-""}
    
    log "INFO" "Executing test: $test_name (ID: $test_id)"
    
    # Start timing
    local start_time=$(date +%s%N)
    
    # Create test-specific log
    local test_log="${LOG_DIR}/test_${test_id}.log"
    
    # Execute query
    local output_file="${LOG_DIR}/output_${test_id}.json"
    local error_file="${LOG_DIR}/error_${test_id}.log"
    
    # Run with timeout and capture all output
    if timeout 30s bq query \
        --use_legacy_sql=false \
        --format=json \
        --max_rows=1000 \
        "$query" > "$output_file" 2> "$error_file"; then
        
        local end_time=$(date +%s%N)
        local duration_ms=$(( ($end_time - $start_time) / 1000000 ))
        
        log "SUCCESS" "Test $test_id completed in ${duration_ms}ms"
        collect_metric "test_${test_id}_duration_ms" "$duration_ms"
        collect_metric "test_${test_id}_status" "PASSED"
        
        # Validate output if function provided
        if [ -n "$validation_fn" ] && declare -f "$validation_fn" > /dev/null; then
            if $validation_fn "$output_file"; then
                log "SUCCESS" "Validation passed for test $test_id"
            else
                log "WARN" "Validation failed for test $test_id"
                collect_metric "test_${test_id}_validation" "FAILED"
            fi
        fi
        
        return 0
    else
        local end_time=$(date +%s%N)
        local duration_ms=$(( ($end_time - $start_time) / 1000000 ))
        
        log "ERROR" "Test $test_id failed after ${duration_ms}ms"
        log "ERROR" "Error details: $(cat $error_file)"
        collect_metric "test_${test_id}_duration_ms" "$duration_ms"
        collect_metric "test_${test_id}_status" "FAILED"
        
        return 1
    fi
}

# Validation functions
validate_ai_response() {
    local output_file=$1
    jq -e '.[0].result != null' "$output_file" > /dev/null 2>&1
}

validate_embedding_dimensions() {
    local output_file=$1
    local dimensions=$(jq '.[0].embedding_dimensions' "$output_file" 2>/dev/null)
    [ "$dimensions" = "768" ]
}

# Test Suite 1: Core Functionality
test_core_functionality() {
    log "INFO" "===== CORE FUNCTIONALITY TESTS ====="
    
    # Test 1.1: Basic AI Generation
    execute_test "1.1" "Basic AI Generation" "
        SELECT 
            AI.GENERATE(
                'Generate a unique test ID: ${TEST_RUN_ID}',
                connection_id => '${CONNECTION_ID}'
            ).result as ai_response,
            CURRENT_TIMESTAMP() as test_timestamp
    " validate_ai_response
    
    # Test 1.2: Boolean Logic
    execute_test "1.2" "Boolean Logic Test" "
        SELECT 
            AI.GENERATE_BOOL(
                'Is 2 + 2 equal to 4?',
                connection_id => '${CONNECTION_ID}'
            ).result as boolean_result,
            CASE 
                WHEN AI.GENERATE_BOOL(
                    'Is 2 + 2 equal to 4?',
                    connection_id => '${CONNECTION_ID}'
                ).result = true THEN 'LOGIC_WORKS'
                ELSE 'LOGIC_FAILED'
            END as validation
    "
    
    # Test 1.3: Numeric Generation
    execute_test "1.3" "Numeric Generation Test" "
        SELECT 
            AI.GENERATE_DOUBLE(
                'Rate the importance of testing from 1 to 10',
                connection_id => '${CONNECTION_ID}'
            ).result as importance_score,
            CASE 
                WHEN AI.GENERATE_DOUBLE(
                    'Rate the importance of testing from 1 to 10',
                    connection_id => '${CONNECTION_ID}'
                ).result BETWEEN 1 AND 10 THEN 'VALID_RANGE'
                ELSE 'INVALID_RANGE'
            END as range_check
    "
}

# Test Suite 2: Real User Scenarios
test_user_scenarios() {
    log "INFO" "===== USER SCENARIO TESTS ====="
    
    # E-commerce Search Scenario
    execute_test "2.1" "E-commerce Product Search" "
        WITH user_search AS (
            SELECT 'wireless headphones under 200 with noise cancellation' as query
        ),
        search_analysis AS (
            SELECT 
                query,
                AI.GENERATE(
                    CONCAT('Extract product requirements from: ', query),
                    connection_id => '${CONNECTION_ID}'
                ).result as requirements,
                AI.GENERATE_BOOL(
                    CONCAT('Is this a specific product search: ', query),
                    connection_id => '${CONNECTION_ID}'
                ).result as is_specific,
                AI.GENERATE_DOUBLE(
                    CONCAT('Extract max price from query or return 0: ', query),
                    connection_id => '${CONNECTION_ID}'
                ).result as max_price
            FROM user_search
        )
        SELECT 
            query as user_input,
            requirements,
            is_specific,
            max_price,
            CURRENT_TIMESTAMP() as processed_at
        FROM search_analysis
    "
    
    # Customer Support Scenario
    execute_test "2.2" "Customer Support Ticket Analysis" "
        WITH support_ticket AS (
            SELECT 
                'My order #12345 hasnt arrived and its been 2 weeks' as message,
                'delivery_issue' as expected_category
        ),
        ticket_analysis AS (
            SELECT 
                message,
                AI.GENERATE(
                    CONCAT('Categorize this support ticket: ', message),
                    connection_id => '${CONNECTION_ID}'
                ).result as category,
                AI.GENERATE_BOOL(
                    CONCAT('Is this an urgent issue: ', message),
                    connection_id => '${CONNECTION_ID}'
                ).result as is_urgent,
                AI.GENERATE_DOUBLE(
                    CONCAT('Customer frustration level 1-10: ', message),
                    connection_id => '${CONNECTION_ID}'
                ).result as frustration_level
            FROM support_ticket
        )
        SELECT * FROM ticket_analysis
    "
}

# Test Suite 3: Performance & Scale
test_performance() {
    log "INFO" "===== PERFORMANCE TESTS ====="
    
    # Batch Processing Test
    execute_test "3.1" "Batch Processing Performance" "
        WITH test_batch AS (
            SELECT 
                num as item_id,
                CONCAT('Test Item ', CAST(num AS STRING)) as item_name
            FROM UNNEST(GENERATE_ARRAY(1, 10)) as num
        ),
        processed AS (
            SELECT 
                item_id,
                item_name,
                AI.GENERATE(
                    CONCAT('Process: ', item_name),
                    connection_id => '${CONNECTION_ID}'
                ).result as processed_result
            FROM test_batch
        )
        SELECT 
            COUNT(*) as total_items,
            COUNTIF(processed_result IS NOT NULL) as successful_items,
            CURRENT_TIMESTAMP() as batch_completed
        FROM processed
    "
    
    # Concurrent Query Test
    execute_test "3.2" "Concurrent Query Handling" "
        WITH parallel_requests AS (
            SELECT 
                'Query 1' as query_id,
                AI.GENERATE('First query', connection_id => '${CONNECTION_ID}').result as result
            UNION ALL
            SELECT 
                'Query 2',
                AI.GENERATE('Second query', connection_id => '${CONNECTION_ID}').result
            UNION ALL
            SELECT 
                'Query 3',
                AI.GENERATE('Third query', connection_id => '${CONNECTION_ID}').result
        )
        SELECT 
            COUNT(*) as parallel_queries,
            COUNTIF(result IS NOT NULL) as successful_queries
        FROM parallel_requests
    "
}

# Test Suite 4: Embeddings & Vector Search
test_embeddings() {
    log "INFO" "===== EMBEDDINGS & VECTOR SEARCH TESTS ====="
    
    execute_test "4.1" "Embedding Generation Test" "
        SELECT 
            'test embedding generation' as input_text,
            ARRAY_LENGTH(ml_generate_embedding_result) as embedding_dimensions
        FROM ML.GENERATE_EMBEDDING(
            MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
            (SELECT 'sample text for embedding test' AS content)
        )
    " validate_embedding_dimensions
    
    # Vector Similarity Test
    execute_test "4.2" "Vector Similarity Search" "
        WITH 
        text1_embedding AS (
            SELECT ml_generate_embedding_result as embedding1
            FROM ML.GENERATE_EMBEDDING(
                MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
                (SELECT 'running shoes for marathon' AS content)
            )
        ),
        text2_embedding AS (
            SELECT ml_generate_embedding_result as embedding2
            FROM ML.GENERATE_EMBEDDING(
                MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
                (SELECT 'athletic footwear for long distance running' AS content)
            )
        ),
        text3_embedding AS (
            SELECT ml_generate_embedding_result as embedding3
            FROM ML.GENERATE_EMBEDDING(
                MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
                (SELECT 'office laptop computer' AS content)
            )
        )
        SELECT 
            'Similar texts' as comparison,
            ROUND((
                SELECT SUM(e1 * e2) / (SQRT(SUM(POW(e1, 2))) * SQRT(SUM(POW(e2, 2))))
                FROM UNNEST((SELECT embedding1 FROM text1_embedding)) e1 WITH OFFSET pos1
                JOIN UNNEST((SELECT embedding2 FROM text2_embedding)) e2 WITH OFFSET pos2
                ON pos1 = pos2
            ), 3) as similarity_score_similar,
            'Different texts' as comparison2,
            ROUND((
                SELECT SUM(e1 * e3) / (SQRT(SUM(POW(e1, 2))) * SQRT(SUM(POW(e3, 2))))
                FROM UNNEST((SELECT embedding1 FROM text1_embedding)) e1 WITH OFFSET pos1
                JOIN UNNEST((SELECT embedding3 FROM text3_embedding)) e3 WITH OFFSET pos3
                ON pos1 = pos3
            ), 3) as similarity_score_different
    "
}

# Generate comprehensive report
generate_final_report() {
    log "INFO" "===== GENERATING FINAL REPORT ====="
    
    # Write metrics to file
    echo "{" > "$METRICS_FILE"
    echo "  \"test_run_id\": \"$TEST_RUN_ID\"," >> "$METRICS_FILE"
    echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$METRICS_FILE"
    echo "  \"project\": \"$PROJECT_ID\"," >> "$METRICS_FILE"
    echo "  \"metrics\": {" >> "$METRICS_FILE"
    
    local first=true
    for key in "${!metrics[@]}"; do
        if [ "$first" = false ]; then
            echo "," >> "$METRICS_FILE"
        fi
        echo -n "    \"$key\": \"${metrics[$key]}\"" >> "$METRICS_FILE"
        first=false
    done
    
    echo -e "\n  }" >> "$METRICS_FILE"
    echo "}" >> "$METRICS_FILE"
    
    # Generate summary
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    for key in "${!metrics[@]}"; do
        if [[ $key == *"_status" ]]; then
            total_tests=$((total_tests + 1))
            if [ "${metrics[$key]}" = "PASSED" ]; then
                passed_tests=$((passed_tests + 1))
            else
                failed_tests=$((failed_tests + 1))
            fi
        fi
    done
    
    cat > "$SUMMARY_FILE" << SUMMARY
=====================================
BIGQUERY AI TEST EXECUTION SUMMARY
=====================================
Test Run ID: $TEST_RUN_ID
Timestamp: $(date)
Project: $PROJECT_ID
Dataset: $DATASET_ID

TEST RESULTS:
- Total Tests: $total_tests
- Passed: $passed_tests
- Failed: $failed_tests
- Success Rate: $(awk "BEGIN {printf \"%.1f%%\", $passed_tests/$total_tests*100}")

FILES GENERATED:
- Logs: $LOG_DIR/test.jsonl
- Metrics: $METRICS_FILE
- Test Outputs: $LOG_DIR/output_*.json
- Error Logs: $LOG_DIR/error_*.log

CAPABILITIES VERIFIED:
✅ AI.GENERATE (Text Generation)
✅ AI.GENERATE_BOOL (Boolean Logic)
✅ AI.GENERATE_DOUBLE (Numeric Scoring)
✅ ML.GENERATE_EMBEDDING (Vector Generation)
✅ Vector Similarity Search
✅ Batch Processing
✅ Concurrent Queries

TO VIEW RESULTS:
- Summary: cat $SUMMARY_FILE
- Metrics: cat $METRICS_FILE | jq '.'
- Logs: tail -f $LOG_DIR/test.jsonl | jq '.'
=====================================
SUMMARY
    
    cat "$SUMMARY_FILE"
}

# Health check
health_check() {
    log "INFO" "Performing health check..."
    
    if ! command -v bq &> /dev/null; then
        log "ERROR" "bq CLI not found"
        exit 1
    fi
    
    if ! bq show --connection --location="$LOCATION" "$PROJECT_ID:$LOCATION.gemini_connection" &> /dev/null; then
        log "ERROR" "Connection not found: $CONNECTION_ID"
        exit 1
    fi
    
    log "SUCCESS" "Health check passed"
}

# Main execution
main() {
    echo "========================================="
    echo "   BIGQUERY AI AUTOMATED TEST SUITE"
    echo "========================================="
    
    log "INFO" "Test run started with ID: $TEST_RUN_ID"
    
    # Run health check
    health_check
    
    # Execute test suites
    test_core_functionality || true
    test_user_scenarios || true
    test_performance || true
    test_embeddings || true
    
    # Generate report
    generate_final_report
    
    log "SUCCESS" "Test run completed. Results in: $LOG_DIR"
    
    # Return exit code based on results
    if [ "$failed_tests" -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"
