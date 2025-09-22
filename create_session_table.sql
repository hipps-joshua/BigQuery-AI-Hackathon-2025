-- Create a session management system in BigQuery
CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.ai_sessions` (
    session_id STRING,
    turn_number INT64,
    user_input STRING,
    ai_response STRING,
    full_context STRING,
    created_at TIMESTAMP
);

-- Create a stored procedure for contextual queries
CREATE OR REPLACE PROCEDURE `bigquery-ai-hackathon-2025.test_dataset_central.chat_with_context`(
    IN session_id STRING,
    IN user_message STRING,
    OUT ai_response STRING
)
BEGIN
    -- Get previous context
    DECLARE context STRING DEFAULT '';
    
    SET context = (
        SELECT STRING_AGG(
            CONCAT('User: ', user_input, '\nAI: ', ai_response), 
            '\n' 
            ORDER BY turn_number
        )
        FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_sessions`
        WHERE session_id = session_id
    );
    
    -- Generate response with context
    SET ai_response = (
        SELECT AI.GENERATE(
            CONCAT(
                IFNULL(CONCAT('Previous conversation:\n', context, '\n\n'), ''),
                'Current message: ', user_message
            ),
            connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
        ).result
    );
    
    -- Store in session
    INSERT INTO `bigquery-ai-hackathon-2025.test_dataset_central.ai_sessions`
    VALUES (
        session_id,
        (SELECT IFNULL(MAX(turn_number), 0) + 1 
         FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_sessions` 
         WHERE session_id = session_id),
        user_message,
        ai_response,
        CONCAT(context, '\nUser: ', user_message, '\nAI: ', ai_response),
        CURRENT_TIMESTAMP()
    );
END;
