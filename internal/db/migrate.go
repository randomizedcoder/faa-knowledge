package db

import (
	"database/sql"
	"fmt"
)

func Migrate(db *sql.DB, schema, seed string) error {
	if _, err := db.Exec(schema); err != nil {
		return fmt.Errorf("exec schema: %w", err)
	}

	if _, err := db.Exec(seed); err != nil {
		return fmt.Errorf("exec seed: %w", err)
	}

	return nil
}
