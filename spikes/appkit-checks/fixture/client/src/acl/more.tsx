import * as appkit from "@databricks/appkit-ui/react";
import { BARREL_KEY } from "../lib";
import { ALIAS_KEY } from "@/lib/alias-keys";

export function useNamespace() {
  return appkit.useAnalyticsQuery("ns_import", {});
}

export function useBarrel() {
  return appkit.useAnalyticsQuery(BARREL_KEY, {});
}

export function useAlias() {
  return appkit.useAnalyticsQuery(ALIAS_KEY, {});
}
