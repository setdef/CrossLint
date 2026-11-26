import { useAnalyticsQuery, useAnalyticsQuery as useQuery } from "@databricks/appkit-ui/react";
import { QUERY_KEYS, SALES_KEY } from "../lib/query-keys";

const LOCAL_KEY = "hook_const_local";

export function useLiteral() {
  return useAnalyticsQuery("hook_literal", { limit: 10 });
}

export function useTemplate() {
  return useAnalyticsQuery(`hook_template`);
}

export function useLocalConst() {
  return useAnalyticsQuery(LOCAL_KEY, {});
}

export function useImportedConst() {
  return useAnalyticsQuery(SALES_KEY, {});
}

export function useMember() {
  return useAnalyticsQuery(QUERY_KEYS.member, {});
}

export function useAliased() {
  return useQuery("hook_aliased", {});
}

export function useGeneric() {
  return useAnalyticsQuery<{ one: number }>("hook_generic", {});
}

export function useTernary(isA: boolean) {
  return useAnalyticsQuery(isA ? "dynamic_ternary_a" : "dynamic_ternary_b", {});
}

export function usePrefixed(prefix: string) {
  return useAnalyticsQuery(`${prefix}_x`, {});
}

// The key arrives as a parameter: syntax sees only `key`.
function useSection(key: string) {
  return useAnalyticsQuery(key, {});
}

export function useViaParam() {
  return useSection("via_param");
}

export function useObo() {
  return useAnalyticsQuery("obo_used", {});
}

export function useBoth() {
  return useAnalyticsQuery("both_lane", {});
}

// useAnalyticsQuery("only_in_comment")
const notAUse = "only_in_comment is mentioned in a string, not passed anywhere";
export { notAUse };
