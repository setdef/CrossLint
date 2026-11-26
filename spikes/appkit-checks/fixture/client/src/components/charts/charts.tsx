import { BarChart, DataTable, LineChart, PieChart, useChartData } from "@databricks/appkit-ui/react";

const CHART_KEY = "chart_const";

export function Charts() {
  const { data } = useChartData({ queryKey: "use_chart_data", parameters: {} });
  return (
    <>
      <BarChart queryKey="chart_prop" parameters={{}} />
      <LineChart queryKey={"chart_prop_expr"} />
      <DataTable queryKey="table_prop" />
      <PieChart queryKey={CHART_KEY} />
      <pre>{JSON.stringify(data)}</pre>
    </>
  );
}

// A project's own wrapper: it forwards its `query` prop to AppKit's `queryKey`.
export function SalesChart(props: { query: string }) {
  return <BarChart queryKey={props.query} />;
}
