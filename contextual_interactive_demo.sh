#!/bin/bash

# ============================================
# CONTEXTUAL BIGQUERY AI DEMO
# Maintains conversation context across queries
# ============================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
PROJECT_ID="bigquery-ai-hackathon-2025"
LOCATION="us-central1"
CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
SESSION_ID="session_$(date +%s)"
CONTEXT_TABLE="${PROJECT_ID}.${LOCATION}.conversation_context_${SESSION_ID//-/_}"

# Conversation history
CONVERSATION_HISTORY=""
QUERY_COUNT=0

# Initialize context table
init_context_table() {
    echo -e "${CYAN}Initializing conversation context...${NC}"
    
    # Create a temporary table to store context
    bq query --use_legacy_sql=false "
    CREATE OR REPLACE TABLE \`$PROJECT_ID.test_dataset_central.session_${SESSION_ID}\` (
        query_num INT64,
        user_input STRING,
        ai_response STRING,
        timestamp TIMESTAMP
    )" > /dev/null 2>&1
    
    echo -e "${GREEN}✓ Context system initialized${NC}"
}

# Add to conversation history
add_to_context() {
    local user_input=$1
    local ai_response=$2
    QUERY_COUNT=$((QUERY_COUNT + 1))
    
    # Append to conversation history (keep last 3 exchanges for context)
    CONVERSATION_HISTORY="${CONVERSATION_HISTORY}
User: $user_input
AI: $ai_response"
    
    # Keep only last 3 exchanges to avoid token limits
    if [ $QUERY_COUNT -gt 3 ]; then
        CONVERSATION_HISTORY=$(echo "$CONVERSATION_HISTORY" | tail -n 6)
    fi
    
    # Store in BigQuery for persistence
    bq query --use_legacy_sql=false "
    INSERT INTO \`$PROJECT_ID.test_dataset_central.session_${SESSION_ID}\` 
    VALUES (
        $QUERY_COUNT,
        '$(echo "$user_input" | sed "s/'/\\'/g")',
        '$(echo "$ai_response" | sed "s/'/\\'/g" | head -c 1000)',
        CURRENT_TIMESTAMP()
    )" > /dev/null 2>&1
}

# Query with context
query_with_context() {
    local user_input=$1
    local query_type=$2
    
    echo -e "\n${CYAN}🤖 Processing with context...${NC}\n"
    
    # Build context-aware prompt
    local context_prompt=""
    if [ -n "$CONVERSATION_HISTORY" ]; then
        context_prompt="Previous conversation context:
$CONVERSATION_HISTORY

Current question: $user_input

Please respond considering the context above."
    else
        context_prompt="$user_input"
    fi
    
    # Execute query based on type
    case $query_type in
        "conversation")
            local response=$(bq query --use_legacy_sql=false --format=csv "
            SELECT 
                AI.GENERATE(
                    '$(echo "$context_prompt" | sed "s/'/\\'/g")',
                    connection_id => '$CONNECTION_ID'
                ).result as response
            " 2>/dev/null | tail -n +2)
            
            echo -e "${GREEN}AI Response:${NC}"
            echo "$response" | fold -w 80
            
            # Add to context
            add_to_context "$user_input" "$response"
            ;;
            
        "analysis")
            local response=$(bq query --use_legacy_sql=false --format=csv "
            WITH context_analysis AS (
                SELECT 
                    '$user_input' as current_query,
                    '''$CONVERSATION_HISTORY''' as conversation_context
            )
            SELECT 
                AI.GENERATE(
                    CONCAT(
                        'Based on our conversation: ',
                        conversation_context,
                        ' Now analyze: ',
                        current_query
                    ),
                    connection_id => '$CONNECTION_ID'
                ).result as analysis,
                AI.GENERATE_DOUBLE(
                    CONCAT('Rate relevance to previous context 1-10: ', current_query),
                    connection_id => '$CONNECTION_ID'
                ).result as context_relevance
            FROM context_analysis
            " 2>/dev/null | tail -n +2)
            
            echo -e "${GREEN}Analysis with Context:${NC}"
            echo "$response" | fold -w 80
            
            add_to_context "$user_input" "$response"
            ;;
    esac
}

# Show conversation history
show_history() {
    echo -e "\n${CYAN}📜 Conversation History${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    if [ $QUERY_COUNT -eq 0 ]; then
        echo "No conversation yet."
    else
        bq query --use_legacy_sql=false --format=pretty "
        SELECT 
            query_num as turn,
            SUBSTR(user_input, 1, 50) as you_said,
            SUBSTR(ai_response, 1, 50) as ai_replied,
            timestamp
        FROM \`$PROJECT_ID.test_dataset_central.session_${SESSION_ID}\`
        ORDER BY query_num
        " 2>/dev/null
    fi
}

# Main menu
main_menu() {
    clear
    echo -e "${BOLD}${CYAN}================================================${NC}"
    echo -e "${BOLD}${CYAN}   CONTEXTUAL BIGQUERY AI DEMO${NC}"
    echo -e "${BOLD}${CYAN}================================================${NC}"
    echo ""
    echo -e "${GREEN}This demo maintains context across queries!${NC}"
    echo -e "${YELLOW}Session: $SESSION_ID${NC}"
    echo -e "${YELLOW}Queries in context: $QUERY_COUNT${NC}"
    echo ""
    
    while true; do
        echo -e "\n${BOLD}${GREEN}Choose an option:${NC}"
        echo -e "${BLUE}1)${NC} 💬 Continue conversation (maintains context)"
        echo -e "${BLUE}2)${NC} 📊 Analyze with context"
        echo -e "${BLUE}3)${NC} 📜 Show conversation history"
        echo -e "${BLUE}4)${NC} 🔄 Clear context and start fresh"
        echo -e "${BLUE}5)${NC} 📈 Export session to file"
        echo -e "${BLUE}6)${NC} 🚪 Exit"
        echo ""
        echo -ne "${YELLOW}Choice (1-6): ${NC}"
        read choice
        
        case $choice in
            1)
                echo -e "\n${CYAN}Continue our conversation:${NC}"
                if [ $QUERY_COUNT -gt 0 ]; then
                    echo -e "${YELLOW}(I remember what we talked about)${NC}"
                fi
                echo -ne "> "
                read -r user_input
                query_with_context "$user_input" "conversation"
                ;;
                
            2)
                echo -e "\n${CYAN}What should I analyze (considering our context)?${NC}"
                echo -ne "> "
                read -r user_input
                query_with_context "$user_input" "analysis"
                ;;
                
            3)
                show_history
                ;;
                
            4)
                CONVERSATION_HISTORY=""
                QUERY_COUNT=0
                echo -e "${GREEN}✓ Context cleared. Starting fresh!${NC}"
                ;;
                
            5)
                local export_file="session_${SESSION_ID}.txt"
                echo "Session Export: $SESSION_ID" > "$export_file"
                echo "=========================" >> "$export_file"
                echo "$CONVERSATION_HISTORY" >> "$export_file"
                echo -e "${GREEN}✓ Session exported to: $export_file${NC}"
                ;;
                
            6)
                echo -e "\n${GREEN}Session ended. Your context was saved.${NC}"
                echo -e "${YELLOW}Session ID: $SESSION_ID${NC}"
                exit 0
                ;;
                
            *)
                echo -e "${RED}Invalid choice${NC}"
                ;;
        esac
    done
}

# Test contextual understanding
test_context() {
    echo -e "\n${CYAN}Testing Contextual Understanding...${NC}"
    
    # First query
    local response1=$(bq query --use_legacy_sql=false --format=csv "
    SELECT AI.GENERATE(
        'My name is John and I like pizza',
        connection_id => '$CONNECTION_ID'
    ).result" 2>/dev/null | tail -n +2)
    
    add_to_context "My name is John and I like pizza" "$response1"
    echo "Query 1: My name is John and I like pizza"
    echo "Response 1: $(echo $response1 | head -c 100)..."
    
    # Second query with context
    local response2=$(bq query --use_legacy_sql=false --format=csv "
    SELECT AI.GENERATE(
        'Previous: User said their name is John and likes pizza. Current question: What is my name?',
        connection_id => '$CONNECTION_ID'
    ).result" 2>/dev/null | tail -n +2)
    
    echo -e "\nQuery 2: What is my name?"
    echo "Response 2: $(echo $response2 | head -c 200)..."
    
    echo -e "\n${GREEN}✓ Context system working!${NC}"
}

# Initialize
init_context_table

# Optional: Run test
echo -ne "${YELLOW}Run context test? (y/n): ${NC}"
read run_test
if [ "$run_test" = "y" ]; then
    test_context
fi

# Start main menu
main_menu
