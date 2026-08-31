// Minimal usage example — not part of the published package (see
// package.json "files"), just a reference for how a consumer wires things
// up. Run it yourself with any React setup by importing "@bytecats/ui-kit"
// and "@bytecats/ui-kit/styles.css" from a real install.
import * as React from "react";

import { Badge } from "./components/ui/badge";
import { Button } from "./components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "./components/ui/card";
import { Input } from "./components/ui/input";
import { Label } from "./components/ui/label";

export function Demo() {
  return (
    <Card className="mx-auto max-w-sm">
      <CardHeader>
        <CardTitle>Invite a teammate</CardTitle>
        <CardDescription>
          They will get an email with a link to join.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="demo-email">Email</Label>
          <Input id="demo-email" type="email" placeholder="teammate@bytecats.codes" />
        </div>
        <Badge variant="secondary">Neutral theme (default)</Badge>
      </CardContent>
      <CardFooter className="justify-end gap-2">
        <Button variant="ghost">Cancel</Button>
        <Button>Send invite</Button>
      </CardFooter>
    </Card>
  );
}

// To try the Stone theme instead, set data-ui-theme="stone" on <html> (or
// any ancestor element) — no rebuild, no JS required:
//
//   <html data-ui-theme="stone">
