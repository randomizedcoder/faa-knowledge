package database

import "embed"

//go:embed schema.sql seed.sql
var SQL embed.FS
