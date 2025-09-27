package database

import (
	"context"
	"sync"
	"time"

	"gorm.io/gorm/logger"
)

// QueryLog represents a single SQL query log entry
type QueryLog struct {
	ID        int           `json:"id"`
	SQL       string        `json:"sql"`
	Duration  time.Duration `json:"duration"`
	Rows      int64         `json:"rows"`
	Error     string        `json:"error,omitempty"`
	Timestamp time.Time     `json:"timestamp"`
}

// QueryLogger stores all executed SQL queries for debugging
type QueryLogger struct {
	mu      sync.RWMutex
	queries []QueryLog
	maxLogs int
	counter int
}

// Global query logger instance
var SQLLogger = NewQueryLogger(100)

// NewQueryLogger creates a new query logger
func NewQueryLogger(maxLogs int) *QueryLogger {
	return &QueryLogger{
		queries: make([]QueryLog, 0, maxLogs),
		maxLogs: maxLogs,
	}
}

// LogQuery logs a SQL query
func (ql *QueryLogger) LogQuery(sql string, duration time.Duration, rows int64, err error) {
	ql.mu.Lock()
	defer ql.mu.Unlock()

	ql.counter++
	log := QueryLog{
		ID:        ql.counter,
		SQL:       sql,
		Duration:  duration,
		Rows:      rows,
		Timestamp: time.Now(),
	}

	if err != nil {
		log.Error = err.Error()
	}

	// Add to beginning to show latest first
	ql.queries = append([]QueryLog{log}, ql.queries...)

	// Keep only maxLogs entries
	if len(ql.queries) > ql.maxLogs {
		ql.queries = ql.queries[:ql.maxLogs]
	}
}

// GetQueries returns all logged queries
func (ql *QueryLogger) GetQueries() []QueryLog {
	ql.mu.RLock()
	defer ql.mu.RUnlock()

	result := make([]QueryLog, len(ql.queries))
	copy(result, ql.queries)
	return result
}

// Clear removes all logged queries
func (ql *QueryLogger) Clear() {
	ql.mu.Lock()
	defer ql.mu.Unlock()
	ql.queries = ql.queries[:0]
}

// GetRecentQueries returns the most recent n queries
func (ql *QueryLogger) GetRecentQueries(n int) []QueryLog {
	ql.mu.RLock()
	defer ql.mu.RUnlock()

	if n > len(ql.queries) {
		n = len(ql.queries)
	}

	result := make([]QueryLog, n)
	copy(result, ql.queries[:n])
	return result
}

// Custom GORM logger that integrates with our query logger
type CustomGormLogger struct {
	logger.Interface
}

// Trace implements the logger.Interface
func (l *CustomGormLogger) Trace(ctx context.Context, begin time.Time, fc func() (sql string, rowsAffected int64), err error) {
	// Call original trace
	if l.Interface != nil {
		l.Interface.Trace(ctx, begin, fc, err)
	}

	// Log to our custom logger
	sql, rows := fc()
	duration := time.Since(begin)
	SQLLogger.LogQuery(sql, duration, rows, err)
}
