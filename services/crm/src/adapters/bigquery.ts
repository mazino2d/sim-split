// Audiences on BigQuery: runs a compiled audience against the traits table in
// the warehouse, and says how old that table is (spec AC21).

import { BigQuery } from '@google-cloud/bigquery';
import type { CompiledQuery } from '../audience_sql.ts';

/** A query may scan at most this much; the traits table is tiny. */
const MAX_BYTES_BILLED = 1024 ** 3;

export interface AudienceSource {
  uids(query: CompiledQuery): Promise<string[]>;
  /** When the traits table was last written. */
  updatedAt(): Promise<Date>;
}

export const createBigQuerySource = (jobProject: string, table: string): AudienceSource => {
  const bigquery = new BigQuery({ projectId: jobProject });
  const [project, dataset, name] = table.split('.');
  return {
    async uids({ sql, params }) {
      const [rows] = await bigquery.query({
        query: sql,
        params,
        location: 'asia-southeast1',
        maximumBytesBilled: String(MAX_BYTES_BILLED),
      });
      return (rows as { uid: string }[]).map((r) => r.uid);
    },
    async updatedAt() {
      const [meta] = await bigquery.dataset(dataset, { projectId: project }).table(name).getMetadata();
      return new Date(Number(meta.lastModifiedTime));
    },
  };
};
