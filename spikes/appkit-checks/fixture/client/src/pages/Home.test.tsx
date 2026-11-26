import { useAnalyticsQuery } from "@databricks/appkit-ui/react";

// A test file that passes a key. A project's policy decides whether this counts as a use.
export const probe = () => useAnalyticsQuery("only_in_test", {});
