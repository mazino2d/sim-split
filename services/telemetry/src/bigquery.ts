// Appends rows to simsplit_raw through the BigQuery Storage Write API default
// stream: free up to 2 TiB a month, unlike legacy streaming inserts (AC22).

import { adapt, managedwriter, protos } from '@google-cloud/bigquery-storage';
import type { Sink } from './handler.ts';
import type { ErrorReportRow, UsageEventRow } from './schema.ts';

const { WriterClient, JSONWriter } = managedwriter;

type Writer = InstanceType<typeof JSONWriter>;

export function createBigQuerySink(projectId: string, datasetId: string): Sink {
  const client = new WriterClient({ projectId });
  const writers = new Map<string, Promise<Writer>>();

  const writer = (table: string): Promise<Writer> => {
    let w = writers.get(table);
    if (!w) {
      w = open(table);
      writers.set(table, w);
      // A failed connection is retried on the next request.
      w.catch(() => writers.delete(table));
    }
    return w;
  };

  const open = async (table: string): Promise<Writer> => {
    const destinationTable = `projects/${projectId}/datasets/${datasetId}/tables/${table}`;
    const stream = await client.getWriteStream({
      streamId: `${destinationTable}/streams/_default`,
      view: protos.google.cloud.bigquery.storage.v1.WriteStreamView.FULL,
    });
    const protoDescriptor = adapt.convertStorageSchemaToProto2Descriptor(stream.tableSchema!, 'root');
    const connection = await client.createStreamConnection({
      streamId: managedwriter.DefaultStream,
      destinationTable,
    });
    return new JSONWriter({ connection, protoDescriptor });
  };

  const append = async (table: string, rows: object[]): Promise<void> => {
    const w = await writer(table);
    const result = await w.appendRows(rows as never).getResult();
    const errors = result.rowErrors ?? [];
    if (result.error || errors.length > 0) {
      writers.delete(table);
      w.close();
      throw new Error(`append to ${table} failed: ${result.error?.message ?? JSON.stringify(errors)}`);
    }
  };

  return {
    writeErrorReports: (rows: ErrorReportRow[]) => append('error_reports', rows),
    writeUsageEvents: (rows: UsageEventRow[]) => append('usage_events', rows),
  };
}
