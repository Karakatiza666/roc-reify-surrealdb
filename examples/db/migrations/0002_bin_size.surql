-- reify-surrealdb migration 0002_bin_size target V4 from c2cc81affaaa4cba5d88661913e404a736ddc7f2de38392a34861a60e857f4e7
DEFINE FIELD OVERWRITE size ON bin TYPE int DEFAULT 1 MIGRATE EXISTING ROWS AS m_c2cc81af_bin_size USING 1;
-- reify: commit
DEFINE INDEX OVERWRITE bin_size_index ON bin FIELDS size;
