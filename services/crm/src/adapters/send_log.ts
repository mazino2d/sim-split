// SendLog on BigQuery: appends simsplit_raw.crm_sends through the Storage
// Write API default stream (free up to 2 TiB a month), like the telemetry
// endpoint. Rows are buffered per request and written once at its end.

import { adapt, managedwriter, protos } from '@google-cloud/bigquery-storage';
import type { Log, SendLog, SendRow } from '../ports.ts';

const { WriterClient, JSONWriter } = managedwriter;

/** dataset: "<project>.<dataset>" of simsplit_raw. */
export const createBigQuerySendLog = (dataset: string, log: Log): SendLog => {
  const [projectId, datasetId] = dataset.split('.');
  const client = new WriterClient({ projectId });
  let writer: Promise<InstanceType<typeof JSONWriter>> | undefined;
  let buffer: SendRow[] = [];

  const open = async () => {
    const destinationTable = `projects/${projectId}/datasets/${datasetId}/tables/crm_sends`;
    const stream = await client.getWriteStream({
      streamId: `${destinationTable}/streams/_default`,
      view: protos.google.cloud.bigquery.storage.v1.WriteStreamView.FULL,
    });
    const protoDescriptor = adapt.convertStorageSchemaToProto2Descriptor(stream.tableSchema!, 'root');
    const connection = await client.createStreamConnection({ streamId: managedwriter.DefaultStream, destinationTable });
    return new JSONWriter({ connection, protoDescriptor });
  };

  return {
    record(row) {
      buffer.push(row);
    },
    async flush() {
      if (!buffer.length) return;
      const rows = buffer;
      buffer = [];
      try {
        writer ??= open();
        const w = await writer;
        // The JSON writer converts Date values for TIMESTAMP columns, as in telemetry.
        const result = await w.appendRows(rows.map((r) => ({ ...r, sent_at: new Date(r.sent_at) })) as never).getResult();
        if (result.error || (result.rowErrors ?? []).length) throw new Error(result.error?.message ?? 'row errors');
      } catch (e) {
        writer = undefined;
        // The send log is for the dashboard; losing rows must not fail a send.
        log({ severity: 'WARNING', kind: 'send_log_failed', rows: rows.length, message: (e as Error).message });
      }
    },
  };
};
