import React from "react";
import { createRoot } from "react-dom/client";
import KuPoVi from "./KuPoVi";
import "./index.css";

const root = createRoot(document.getElementById("root"));
root.render(
  <React.StrictMode>
    <KuPoVi />
  </React.StrictMode>
);
