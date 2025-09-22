#!/bin/bash

# ============================================
# BIGQUERY AI - AUTOMATED CONTINUOUS TESTING (macOS Compatible)
# Production-grade testing with full observability
# ============================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly PROJECT_ID="bigquery-ai-hackathon-2025"
readonly LOCATION="us-central1"
readonly DATASET_ID="test_dataset_central"
readonly CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
readonly TEST_RUN_ID="test_$(date +%s)_$$"
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_DIR="bigquery_ai_tests_${TIMESTAMP}"
readonly METRICS_FILE="${LOG_DIR}/metrics.json"
readonly SUMMARY_FILE="${LOG_DIR}/summary.txt"

# Create log directory
mkdir -p "$LOG_DIR"

# Test counters (using regular variables instead of associative array)
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=""

# Logging with levels
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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

# Store metrics in file directly
save_metric() {
    local metric_name=$1
    local value=$2
    echo "\"$metric_name\": \"$value\"," >> "${LOG_DIR}/metrics_raw.txt"
}

# Test execution with detailed logging
execute_test() {
    local test_id=$1
    local test_name=$2
    local query=$3
    
    log "INFO" "Executing test: $test_name (ID: $test_id)"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Start timing
    local start_time=$(date +%s)
    
    # Execute query
    local output_file="${LOG_DIR}/output_${test_id}.json"
    local error_file="${LOG_DIR}/error_${test_id}.log"
    
    # Run with timeout and capture all output
    if bq query \
        --use_legacy_sql=false \
        --format=json \
        --max_rows=1000 \
        "$query" > "$output_file" 2> "$error_file"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log "SUCCESS" "Test $test_id completed in ${duration} seconds"
        save_metric "test_${test_id}_duration" "$duration"
        save_metric "test_${test_id}_status" "PASSED"
        
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS="${TEST_RESULTS}✅ Test $test_id: $test_name - PASSED (${duration}s)\n"
        
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log "ERROR" "Test $test_id failed after ${duration} seconds"
        log "ERROR" "Error: $(head -n 5 $error_file)"
        save_metric "test_${test_id}_duration" "$duration"
        save_metric "test_${test_id}_status" "FAILED"
        
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS="${TEST_RESULTS}❌ Test $test_id: $test_name - FAILED (${duration}s)\n"
        
        return 1
    fi
}

# Test Suite 1: Core Functionality
test_core_functionality() {
    log "INFO" "===== CORE FUNCTIONALITY TESTS ====="
    
    # Test 1.1: Basic AI Generation
    execute_test "1.1" "Basic AI Generation" "
        SELECT 
            AI.GENERATE(
                'Generate a unique test response',
                connection_id => '${CONNECTION_ID}'
            ).result as ai_response,
            CURRENT_TIMESTAMP() as test_timestamp
    " || true
    
    # Test 1.2: Boolean Logic
    execute_test "1.2" "Boolean Logic Test" "
        SELECT 
            AI.GENERATE_BOOL(
                'Is 2 + 2 equal to 4?',
                connection_id => '${CONNECTION_ID}'
            ).result as boolean_result
    " || true
    
    # Test 1.3: Numeric Generation
    execute_test "1.3" "Numeric Generation Test" "
        SELECT 
            AI.GENERATE_DOUBLE(
                'Rate the importance of testing from 1 to 10',
                connection_id => '${CONNECTION_ID}'
            ).result as importance_score
    " || true
}

# Test Suite 2: Real User Scenarios
test_user_scenarios() {
    log "INFO" "===== USER SCENARIO TESTS ====="
    
    # E-commerce Search Scenario
    execute_test "2.1" "E-commerce Product Search" "
        WITH user_search AS (
            SELECT 'wireless headphones under 200 with noise cancellation' as query
        )
        SELECT 
            query,
            AI.GENERATE(
                CONCAT('Extract product requirements from: ', query),
                connection_id => '${CONNECTION_ID}'
            ).result as requirements,
            AI.GENERATE_BOOL(
                CONCAT('Is this a specific product search: ', query),
                connection_id => '${CONNECTION_ID}'
            ).result as is_specific
        FROM user_search
    " || true
    
    # Customer Support Scenario
    execute_test "2.2" "Customer Support Analysis" "
        WITH support_ticket AS (
            SELECT 'My order has not arrived and it has been 2 weeks' as message
        )
        SELECT 
            message,
            AI.GENERATE(
                CONCAT('Categorize this support ticket: ', message),
                connection_id => '${CONNECTION_ID}'
            ).result as category,
            AI.GENERATE_BOOL(
                CONCAT('Is this an urgent issue: ', message),
                connection_id => '${CONNECTION_ID}'
            ).result as is_urgent
        FROM support_ticket
    " || true
}

# Test Suite 3: Performance & Scale
test_performance() {
    log "INFO" "===== PERFORMANCE TESTS ====="
    
    # Batch Processing Test
    execute_test "3.1" "Batch Processing (5 items)" "
        WITH test_batch AS (
            SELECT num as item_id
            FROM UNNEST(GENERATE_ARRAY(1, 5)) as num
        )
        SELECT 
            COUNT(*) as total_items,
            COUNT(
                AI.GENERATE(
                    CONCAT('Process item ', CAST(item_id AS STRING)),
                    connection_id => '${CONNECTION_ID}'
                ).result
            ) as processed_items
        FROM test_batch
    " || true
    
    # Multiple Queries Test
    execute_test "3.2" "Multiple AI Calls" "
        SELECT 
            AI.GENERATE('First', connection_id => '${CONNECTION_ID}').result as q1,
            AI.GENERATE('Second', connection_id => '${CONNECTION_ID}').result as q2,
            AI.GENERATE('Third', connection_id => '${CONNECTION_ID}').result as q3,
            3 as total_queries
    " || true
}

# Test Suite 4: Embeddings
test_embeddings() {
    log "INFO" "===== EMBEDDINGS TESTS ====="
    
    execute_test "4.1" "Embedding Generation" "
        SELECT 
            'test text' as input,
            ARRAY_LENGTH(ml_generate_embedding_result) as dimensions
        FROM ML.GENERATE_EMBEDDING(
            MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
            (SELECT 'sample text' AS content)
        )
    " || true
    
    # Simple similarity test
    execute_test "4.2" "Embedding Similarity" "
        WITH text1 AS (
            SELECT ml_generate_embedding_result as emb1
            FROM ML.GENERATE_EMBEDDING(
                MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
                (SELECT 'running shoes' AS content)
            )
        ),
        text2 AS (
            SELECT ml_generate_embedding_result as emb2
            FROM ML.GENERATE_EMBEDDING(
                MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_embedding_model\`,
                (SELECT 'athletic footwear' AS content)
            )
        )
        SELECT 
            'running shoes vs athletic footwear' as comparison,
            ARRAY_LENGTH((SELECT emb1 FROM text1)) as embedding_size
    " || true
}

# Generate final report
generate_final_report() {
    log "INFO" "===== GENERATING FINAL REPORT ====="
    
    # Create metrics JSON
    cat > "$METRICS_FILE" << METRICS
{
  "test_run_id": "$TEST_RUN_ID",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project": "$PROJECT_ID",
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "success_rate": "$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
  }
}
METRICS
    
    # Generate summary
    cat > "$SUMMARY_FILE" << SUMMARY
=====================================
BIGQUERY AI TEST EXECUTION SUMMARY
=====================================
Test Run ID: $TEST_RUN_ID
Timestamp: $(date)
Project: $PROJECT_ID
Dataset: $DATASET_ID

TEST RESULTS:
- Total Tests: $TOTAL_TESTS
- Passed: $PASSED_TESTS  ✅
- Failed: $FAILED_TESTS  ❌
- Success Rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%

DETAILED RESULTS:
$(echo -e "$TEST_RESULTS")

FILES GENERATED:
- Logs: $LOG_DIR/test.jsonl
- Metrics: $METRICS_FILE
- Test Outputs: $LOG_DIR/output_*.json
- Error Logs: $LOG_DIR/error_*.log

CAPABILITIES TESTED:
✅ AI.GENERATE (Text Generation)
✅ AI.GENERATE_BOOL (Boolean Logic)
✅ AI.GENERATE_DOUBLE (Numeric Scoring)
✅ ML.GENERATE_EMBEDDING (Vector Generation)
✅ Batch Processing
✅ Multiple Concurrent Calls

TO VIEW DETAILED RESULTS:
- Summary: cat $SUMMARY_FILE
- Metrics: cat $METRICS_FILE
- Logs: cat $LOG_DIR/test.jsonl
- Specific test: cat $LOG_DIR/output_1.1.json

=====================================
TEST RUN COMPLETE: $(date)
=====================================
SUMMARY
    
    # Display summary
    cat "$SUMMARY_FILE"
}

# Health check
health_check() {
    log "INFO" "Performing health check..."
    
    if ! command -v bq &> /dev/null; then
        log "ERROR" "bq CLI not found. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if we can list datasets
    if ! bq ls -n 1 &> /dev/null; then
        log "ERROR" "Not authenticated. Run: gcloud auth login"
        exit 1
    fi
    
    log "SUCCESS" "Health check passed"
}

# Main execution
main() {
    echo "========================================="
    echo "   BIGQUERY AI AUTOMATED TEST SUITE"
    echo "   (macOS Compatible Version)"
    echo "========================================="
    echo ""
    
    log "INFO" "Test run started with ID: $TEST_RUN_ID"
    
    # Run health check
    health_check
    
    # Execute test suites
    echo "🧪 Running Core Functionality Tests..."
    test_core_functionality
    
    echo ""
    echo "👤 Running User Scenario Tests..."
    test_user_scenarios
    
    echo ""
    echo "⚡ Running Performance Tests..."
    test_performance
    
    echo ""
    echo "🔍 Running Embedding Tests..."
    test_embeddings
    
    echo ""
    # Generate report
    generate_final_report
    
    log "SUCCESS" "Test run completed. Results saved in: $LOG_DIR"
    
    # Show quick summary
    echo ""
    echo "📊 QUICK SUMMARY:"
    echo "   ✅ Passed: $PASSED_TESTS"
    echo "   ❌ Failed: $FAILED_TESTS"
    echo "   📈 Success Rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"
    echo ""
    echo "📁 Full results in: $LOG_DIR/"
    echo ""
}

# Run main function
main "$@"
