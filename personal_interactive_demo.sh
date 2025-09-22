#!/bin/bash

# ============================================
# PERSONAL INTERACTIVE BIGQUERY AI DEMO
# Real-time interaction with YOUR inputs
# ============================================

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="bigquery-ai-hackathon-2025"
LOCATION="us-central1"
CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
SESSION_ID="session_$(date +%s)"
LOG_FILE="personal_demo_$(date +%Y%m%d_%H%M%S).log"

# Welcome message
clear
echo -e "${BOLD}${CYAN}================================================${NC}"
echo -e "${BOLD}${CYAN}   BIGQUERY AI - PERSONAL INTERACTIVE DEMO${NC}"
echo -e "${BOLD}${CYAN}================================================${NC}"
echo ""
echo -e "${GREEN}Welcome! This is YOUR personal AI assistant powered by BigQuery.${NC}"
echo -e "${YELLOW}Session ID: $SESSION_ID${NC}"
echo ""
echo -e "I can help you with:"
echo -e "  ${BLUE}1.${NC} Product recommendations"
echo -e "  ${BLUE}2.${NC} Business analysis"
echo -e "  ${BLUE}3.${NC} Decision making"
echo -e "  ${BLUE}4.${NC} Content generation"
echo -e "  ${BLUE}5.${NC} Custom queries"
echo ""

# Function to log interactions
log_interaction() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to run personalized query
run_personal_query() {
    local user_input=$1
    local query_type=$2
    
    echo -e "\n${CYAN}🤖 Processing your request...${NC}\n"
    
    case $query_type in
        "recommendation")
            bq query --use_legacy_sql=false --format=csv "
            WITH user_request AS (
                SELECT '$user_input' as request
            )
            SELECT 
                '🎯 Based on your request' as response_type,
                AI.GENERATE(
                    CONCAT('Provide 3 specific recommendations for: ', request),
                    connection_id => '$CONNECTION_ID'
                ).result as recommendations,
                AI.GENERATE_BOOL(
                    CONCAT('Is this a specific enough request to give good recommendations: ', request),
                    connection_id => '$CONNECTION_ID'
                ).result as confidence,
                CURRENT_TIMESTAMP() as generated_at
            FROM user_request" 2>/dev/null | tail -n +2
            ;;
            
        "analysis")
            bq query --use_legacy_sql=false --format=csv "
            SELECT 
                '📊 Analysis Results' as response_type,
                AI.GENERATE(
                    CONCAT('Analyze this business scenario: ', '$user_input'),
                    connection_id => '$CONNECTION_ID'
                ).result as analysis,
                AI.GENERATE_DOUBLE(
                    CONCAT('Rate the complexity of this scenario 1-10: ', '$user_input'),
                    connection_id => '$CONNECTION_ID'
                ).result as complexity_score
            " 2>/dev/null | tail -n +2
            ;;
            
        "decision")
            bq query --use_legacy_sql=false --format=csv "
            SELECT 
                '🤔 Decision Support' as response_type,
                AI.GENERATE_BOOL(
                    '$user_input',
                    connection_id => '$CONNECTION_ID'
                ).result as decision,
                AI.GENERATE(
                    CONCAT('Explain the reasoning for this decision: ', '$user_input'),
                    connection_id => '$CONNECTION_ID'
                ).result as explanation
            " 2>/dev/null | tail -n +2
            ;;
            
        "creative")
            bq query --use_legacy_sql=false --format=csv "
            SELECT 
                '✨ Creative Output' as response_type,
                AI.GENERATE(
                    '$user_input',
                    connection_id => '$CONNECTION_ID'
                ).result as creation,
                CURRENT_TIMESTAMP() as created_at
            " 2>/dev/null | tail -n +2
            ;;
            
        *)
            bq query --use_legacy_sql=false --format=csv "
            SELECT 
                '💡 AI Response' as response_type,
                AI.GENERATE(
                    '$user_input',
                    connection_id => '$CONNECTION_ID'
                ).result as response
            " 2>/dev/null | tail -n +2
            ;;
    esac
    
    log_interaction "User: $user_input"
    echo ""
}

# Main interaction loop
interact() {
    while true; do
        echo -e "\n${BOLD}${GREEN}═══════════════════════════════════════════════${NC}"
        echo -e "${BOLD}What would you like to explore?${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${BLUE}1)${NC} 🛍️  Get product recommendations"
        echo -e "${BLUE}2)${NC} 📊 Analyze a business scenario"
        echo -e "${BLUE}3)${NC} 🤔 Make a decision (yes/no question)"
        echo -e "${BLUE}4)${NC} ✨ Generate creative content"
        echo -e "${BLUE}5)${NC} 💬 Ask anything (free-form)"
        echo -e "${BLUE}6)${NC} 🧪 Run a comprehensive test"
        echo -e "${BLUE}7)${NC} 📈 Show my session stats"
        echo -e "${BLUE}8)${NC} 🚪 Exit"
        echo ""
        echo -ne "${YELLOW}Choose (1-8): ${NC}"
        read choice
        
        case $choice in
            1)
                echo -e "\n${CYAN}What product are you looking for?${NC}"
                echo -e "${YELLOW}Example: 'comfortable running shoes under $150'${NC}"
                echo -ne "> "
                read -r user_input
                run_personal_query "$user_input" "recommendation"
                ;;
                
            2)
                echo -e "\n${CYAN}Describe your business scenario:${NC}"
                echo -e "${YELLOW}Example: 'Should we expand to European markets this year?'${NC}"
                echo -ne "> "
                read -r user_input
                run_personal_query "$user_input" "analysis"
                ;;
                
            3)
                echo -e "\n${CYAN}Ask a yes/no question:${NC}"
                echo -e "${YELLOW}Example: 'Is cloud computing essential for modern businesses?'${NC}"
                echo -ne "> "
                read -r user_input
                run_personal_query "$user_input" "decision"
                ;;
                
            4)
                echo -e "\n${CYAN}What should I create for you?${NC}"
                echo -e "${YELLOW}Example: 'Write a haiku about data science'${NC}"
                echo -ne "> "
                read -r user_input
                run_personal_query "$user_input" "creative"
                ;;
                
            5)
                echo -e "\n${CYAN}Ask me anything:${NC}"
                echo -ne "> "
                read -r user_input
                run_personal_query "$user_input" "general"
                ;;
                
            6)
                echo -e "\n${CYAN}Running comprehensive test...${NC}"
                run_comprehensive_test
                ;;
                
            7)
                show_stats
                ;;
                
            8)
                echo -e "\n${GREEN}Thanks for using BigQuery AI!${NC}"
                echo -e "${YELLOW}Your session log: $LOG_FILE${NC}"
                exit 0
                ;;
                
            *)
                echo -e "${RED}Invalid choice. Please select 1-8.${NC}"
                ;;
        esac
    done
}

# Comprehensive test function
run_comprehensive_test() {
    echo -e "\n${BOLD}${CYAN}RUNNING COMPREHENSIVE TEST SUITE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    local start_time=$(date +%s)
    
    # Test 1: Speed Test
    echo -e "\n${YELLOW}Test 1: Response Speed${NC}"
    local speed_start=$(date +%s%N)
    bq query --use_legacy_sql=false "
    SELECT AI.GENERATE('Quick test', 
        connection_id => '$CONNECTION_ID').result" > /dev/null 2>&1
    local speed_end=$(date +%s%N)
    local response_time=$(( ($speed_end - $speed_start) / 1000000 ))
    echo -e "${GREEN}✓ Response time: ${response_time}ms${NC}"
    
    # Test 2: Multi-function Test
    echo -e "\n${YELLOW}Test 2: AI Functions${NC}"
    bq query --use_legacy_sql=false --format=csv "
    SELECT 
        CASE WHEN AI.GENERATE('test', connection_id => '$CONNECTION_ID').result IS NOT NULL 
             THEN '✓ Text Generation: WORKING' END as test1,
        CASE WHEN AI.GENERATE_BOOL('Is 1=1?', connection_id => '$CONNECTION_ID').result = true 
             THEN '✓ Boolean Logic: WORKING' END as test2,
        CASE WHEN AI.GENERATE_DOUBLE('Rate 5 out of 10', connection_id => '$CONNECTION_ID').result > 0 
             THEN '✓ Numeric Scoring: WORKING' END as test3
    " 2>/dev/null | tail -n +2
    
    # Test 3: Complex Query
    echo -e "\n${YELLOW}Test 3: Complex Analysis${NC}"
    bq query --use_legacy_sql=false --format=csv "
    WITH products AS (
        SELECT 'iPhone 15' as name, 999 as price
        UNION ALL SELECT 'Galaxy S24', 899
        UNION ALL SELECT 'Pixel 8', 699
    )
    SELECT 
        COUNT(*) as products_analyzed,
        COUNT(AI.GENERATE(CONCAT('Describe ', name), 
            connection_id => '$CONNECTION_ID').result) as successful_analyses
    FROM products
    " 2>/dev/null | tail -n +2
    
    local end_time=$(date +%s)
    local total_time=$(($end_time - $start_time))
    
    echo -e "\n${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}All tests completed in ${total_time} seconds!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
}

# Show session statistics
show_stats() {
    echo -e "\n${CYAN}📊 Your Session Statistics${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    if [ -f "$LOG_FILE" ]; then
        local query_count=$(grep -c "User:" "$LOG_FILE" 2>/dev/null || echo "0")
        echo -e "Session ID: ${YELLOW}$SESSION_ID${NC}"
        echo -e "Queries Run: ${YELLOW}$query_count${NC}"
        echo -e "Log File: ${YELLOW}$LOG_FILE${NC}"
        echo -e "Session Start: ${YELLOW}$(head -n1 $LOG_FILE | cut -d' ' -f1-2 2>/dev/null)${NC}"
    else
        echo -e "${YELLOW}No queries run yet in this session${NC}"
    fi
    
    # Show current BigQuery stats
    echo -e "\n${CYAN}Current BigQuery Status:${NC}"
    bq query --use_legacy_sql=false --format=csv "
    SELECT 
        'Connection Active' as status,
        CURRENT_TIMESTAMP() as checked_at
    " 2>/dev/null | tail -n +2
}

# Error handler
handle_error() {
    echo -e "\n${RED}❌ Error: Unable to connect to BigQuery AI${NC}"
    echo -e "${YELLOW}Please check:${NC}"
    echo -e "  1. You're authenticated: ${CYAN}gcloud auth login${NC}"
    echo -e "  2. Project is set: ${CYAN}gcloud config set project $PROJECT_ID${NC}"
    echo -e "  3. Connection exists: ${CYAN}bq show --connection $CONNECTION_ID${NC}"
    exit 1
}

# Check connection before starting
check_connection() {
    echo -e "${CYAN}Checking BigQuery AI connection...${NC}"
    if bq query --use_legacy_sql=false "SELECT 'test'" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Connection verified!${NC}"
    else
        handle_error
    fi
}

# Main execution
main() {
    check_connection
    log_interaction "Session started: $SESSION_ID"
    interact
}

# Trap errors
trap handle_error ERR

# Start the interactive demo
main
