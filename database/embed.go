// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package database

import "embed"

//go:embed schema.sql seed.sql
var SQL embed.FS

//go:embed questions/*.json
var Questions embed.FS
