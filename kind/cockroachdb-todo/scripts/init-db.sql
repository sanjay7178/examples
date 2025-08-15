-- CockroachDB Multi-Tenant Todo Database Schema
-- This script initializes the database with multi-tenant schema

-- Create the main database
CREATE DATABASE IF NOT EXISTS tododb;
USE tododb;

-- Create tenant-specific schemas
CREATE SCHEMA IF NOT EXISTS tenant_a;
CREATE SCHEMA IF NOT EXISTS tenant_b;
CREATE SCHEMA IF NOT EXISTS tenant_c;

-- Create users table for each tenant
CREATE TABLE IF NOT EXISTS tenant_a.users (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    username STRING NOT NULL UNIQUE,
    email STRING NOT NULL UNIQUE,
    password_hash STRING NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_b.users (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    username STRING NOT NULL UNIQUE,
    email STRING NOT NULL UNIQUE,
    password_hash STRING NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tenant_c.users (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    username STRING NOT NULL UNIQUE,
    email STRING NOT NULL UNIQUE,
    password_hash STRING NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- Create todos table for each tenant
CREATE TABLE IF NOT EXISTS tenant_a.todos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES tenant_a.users(id) ON DELETE CASCADE,
    title STRING NOT NULL,
    description STRING,
    completed BOOL DEFAULT false,
    priority INT DEFAULT 1,
    due_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),
    INDEX idx_user_id (user_id),
    INDEX idx_completed (completed),
    INDEX idx_created_at (created_at)
);

CREATE TABLE IF NOT EXISTS tenant_b.todos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES tenant_b.users(id) ON DELETE CASCADE,
    title STRING NOT NULL,
    description STRING,
    completed BOOL DEFAULT false,
    priority INT DEFAULT 1,
    due_date TIMESTAMP,
    tags STRING[],  -- Premium feature: tags
    category STRING, -- Premium feature: categories
    shared_with UUID[], -- Premium feature: sharing
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),
    INDEX idx_user_id (user_id),
    INDEX idx_completed (completed),
    INDEX idx_created_at (created_at),
    INDEX idx_category (category),
    INVERTED INDEX idx_tags (tags)
);

CREATE TABLE IF NOT EXISTS tenant_c.todos (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES tenant_c.users(id) ON DELETE CASCADE,
    title STRING NOT NULL,
    description STRING,
    completed BOOL DEFAULT false,
    priority INT DEFAULT 1,
    due_date TIMESTAMP,
    tags STRING[],  -- Enterprise feature: tags
    category STRING, -- Enterprise feature: categories
    shared_with UUID[], -- Enterprise feature: sharing
    custom_fields JSONB, -- Enterprise feature: custom fields
    workflow_state STRING DEFAULT 'open', -- Enterprise feature: workflows
    estimated_hours DECIMAL, -- Enterprise feature: time tracking
    actual_hours DECIMAL, -- Enterprise feature: time tracking
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),
    INDEX idx_user_id (user_id),
    INDEX idx_completed (completed),
    INDEX idx_created_at (created_at),
    INDEX idx_category (category),
    INDEX idx_workflow_state (workflow_state),
    INVERTED INDEX idx_tags (tags),
    INVERTED INDEX idx_custom_fields (custom_fields)
);

-- Create analytics table for tenant C (Enterprise)
CREATE TABLE IF NOT EXISTS tenant_c.analytics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES tenant_c.users(id) ON DELETE CASCADE,
    event_type STRING NOT NULL,
    event_data JSONB,
    timestamp TIMESTAMP DEFAULT now(),
    INDEX idx_user_id (user_id),
    INDEX idx_event_type (event_type),
    INDEX idx_timestamp (timestamp)
);

-- Insert sample users for each tenant
INSERT INTO tenant_a.users (username, email, password_hash) VALUES
    ('alice_free', 'alice@freetier.com', 'hash_placeholder_1'),
    ('bob_free', 'bob@freetier.com', 'hash_placeholder_2')
ON CONFLICT (username) DO NOTHING;

INSERT INTO tenant_b.users (username, email, password_hash) VALUES
    ('charlie_premium', 'charlie@premium.com', 'hash_placeholder_3'),
    ('diana_premium', 'diana@premium.com', 'hash_placeholder_4'),
    ('eve_premium', 'eve@premium.com', 'hash_placeholder_5')
ON CONFLICT (username) DO NOTHING;

INSERT INTO tenant_c.users (username, email, password_hash) VALUES
    ('frank_enterprise', 'frank@enterprise.com', 'hash_placeholder_6'),
    ('grace_enterprise', 'grace@enterprise.com', 'hash_placeholder_7'),
    ('henry_enterprise', 'henry@enterprise.com', 'hash_placeholder_8'),
    ('iris_enterprise', 'iris@enterprise.com', 'hash_placeholder_9')
ON CONFLICT (username) DO NOTHING;

-- Insert sample todos
INSERT INTO tenant_a.todos (user_id, title, description, completed) 
SELECT id, 'Welcome to Free Tier', 'This is your first todo in the free tier', false 
FROM tenant_a.users WHERE username = 'alice_free'
ON CONFLICT DO NOTHING;

INSERT INTO tenant_a.todos (user_id, title, description, completed) 
SELECT id, 'Upgrade to Premium', 'Consider upgrading for more features', false 
FROM tenant_a.users WHERE username = 'alice_free'
ON CONFLICT DO NOTHING;

INSERT INTO tenant_b.todos (user_id, title, description, completed, tags, category) 
SELECT id, 'Premium Feature Demo', 'This todo has tags and categories', false, ARRAY['demo', 'premium'], 'work' 
FROM tenant_b.users WHERE username = 'charlie_premium'
ON CONFLICT DO NOTHING;

INSERT INTO tenant_b.todos (user_id, title, description, completed, tags, category) 
SELECT id, 'Collaboration Test', 'This todo can be shared with team members', false, ARRAY['collaboration', 'team'], 'work' 
FROM tenant_b.users WHERE username = 'charlie_premium'
ON CONFLICT DO NOTHING;

INSERT INTO tenant_c.todos (user_id, title, description, completed, tags, category, custom_fields, workflow_state, estimated_hours) 
SELECT id, 'Enterprise Dashboard', 'Advanced todo with custom fields and workflow', false, ARRAY['enterprise', 'dashboard'], 'project', 
       '{"project_code": "ENT-001", "budget": 50000, "department": "engineering"}', 'in_progress', 40.0
FROM tenant_c.users WHERE username = 'frank_enterprise'
ON CONFLICT DO NOTHING;

INSERT INTO tenant_c.todos (user_id, title, description, completed, tags, category, custom_fields, workflow_state, estimated_hours) 
SELECT id, 'Analytics Implementation', 'Implement real-time analytics for enterprise features', false, ARRAY['analytics', 'implementation'], 'development',
       '{"project_code": "ENT-002", "priority": "high", "sprint": "2024-Q1"}', 'planning', 80.0
FROM tenant_c.users WHERE username = 'grace_enterprise'
ON CONFLICT DO NOTHING;

-- Insert sample analytics events for tenant C
INSERT INTO tenant_c.analytics (user_id, event_type, event_data)
SELECT u.id, 'todo_created', '{"todo_id": "sample", "category": "project"}'
FROM tenant_c.users u WHERE u.username = 'frank_enterprise'
ON CONFLICT DO NOTHING;

INSERT INTO tenant_c.analytics (user_id, event_type, event_data)
SELECT u.id, 'dashboard_accessed', '{"page": "main_dashboard", "features_used": ["search", "filter"]}'
FROM tenant_c.users u WHERE u.username = 'frank_enterprise'
ON CONFLICT DO NOTHING;

-- Create views for cross-tenant analytics (for demo purposes)
CREATE VIEW IF NOT EXISTS global_stats AS
SELECT 
    'tenant_a' as tenant_id,
    'Free Tier' as tenant_name,
    COUNT(*) as total_todos,
    COUNT(CASE WHEN completed THEN 1 END) as completed_todos
FROM tenant_a.todos
UNION ALL
SELECT 
    'tenant_b' as tenant_id,
    'Premium Tier' as tenant_name,
    COUNT(*) as total_todos,
    COUNT(CASE WHEN completed THEN 1 END) as completed_todos
FROM tenant_b.todos
UNION ALL
SELECT 
    'tenant_c' as tenant_id,
    'Enterprise Tier' as tenant_name,
    COUNT(*) as total_todos,
    COUNT(CASE WHEN completed THEN 1 END) as completed_todos
FROM tenant_c.todos;

-- Create stored procedure for tenant statistics
CREATE OR REPLACE FUNCTION get_tenant_stats(tenant_name STRING)
RETURNS TABLE (
    total_users INT,
    total_todos INT,
    completed_todos INT,
    completion_rate DECIMAL
) AS $$
DECLARE
    schema_name STRING;
BEGIN
    schema_name := tenant_name;
    
    RETURN QUERY EXECUTE format('
        SELECT 
            (SELECT COUNT(*)::INT FROM %I.users) as total_users,
            (SELECT COUNT(*)::INT FROM %I.todos) as total_todos,
            (SELECT COUNT(*)::INT FROM %I.todos WHERE completed = true) as completed_todos,
            CASE 
                WHEN (SELECT COUNT(*) FROM %I.todos) > 0 
                THEN (SELECT COUNT(*)::DECIMAL FROM %I.todos WHERE completed = true) / (SELECT COUNT(*) FROM %I.todos) * 100
                ELSE 0 
            END as completion_rate
    ', schema_name, schema_name, schema_name, schema_name, schema_name, schema_name);
END
$$ LANGUAGE plpgsql;

-- Show final statistics
SELECT 'Database initialization completed successfully' AS status;
SELECT * FROM global_stats;