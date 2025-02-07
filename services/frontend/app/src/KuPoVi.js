import React, { useEffect, useRef, useState } from "react";
import * as d3 from "d3";

const KuPoVi = () => {
  const svgRef = useRef();
  const width = 800;
  const height = 600;
  const [data, setData] = useState({ nodes: [], pods: [] });
  const [previousData, setPreviousData] = useState(null);
  const [displayMode, setDisplayMode] = useState("pod"); // Default to display pod names

  useEffect(() => {
    const fetchData = async () => {
      const backendUrl = window.APP_CONFIG?.BACKEND_URL || "http://localhost:5010";
      try {
        const response = await fetch(`${backendUrl}/api/pods?namespace=default&label=zone&display=label`);
        const newData = await response.json();

        if (JSON.stringify(newData) !== JSON.stringify(previousData)) {
          setData(newData);
          setPreviousData(newData);
        }
      } catch (error) {
        console.error("Error fetching pods:", error);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000); // Poll every 5 seconds
    return () => clearInterval(interval);
  }, [previousData]);

  useEffect(() => {
    if (!data.nodes.length) return;

    const colorDistance = (color1, color2) => {
      const rgb1 = d3.rgb(color1);
      const rgb2 = d3.rgb(color2);
      return Math.sqrt(
        (rgb1.r - rgb2.r) ** 2 +
        (rgb1.g - rgb2.g) ** 2 +
        (rgb1.b - rgb2.b) ** 2
      );
    };
  
    // Threshold distance to exclude red and similar shades
    const red = "#ff0000";
    const purple = "#9467bd";
    const threshold = 150; // Adjust for strictness

    const svg = d3.select(svgRef.current)
      .attr("width", width)
      .attr("height", height);

    const nodes = [
      ...data.nodes.map((n) => ({ id: n.name, type: "node" })),
      ...data.pods.map((pod) => ({
        id: pod.name,
        deployment: pod.deployment, // Include deployment information
        type: "pod",
        parent: pod.node,
        ready: pod.ready
      })),
    ];

    const links = data.pods
      .filter((pod) => pod.node)
      .map((pod) => ({ source: pod.node, target: pod.name }));

    const simulation = d3.forceSimulation(nodes)
      .force(
        "link",
        d3.forceLink(links)
          .id((d) => d.id)
          .distance((d) => (d.target.type === "pod" ? 120 : 300))
      )
      .force(
        "charge",
        d3.forceManyBody().strength((d) => (d.type === "node" ? -800 : -200))
      )
      .force(
        "x",
        d3.forceX().strength(0.1).x((d) =>
          d.type === "node"
            ? width / 4
            : d.parent
            ? width / 2
            : Math.random() * (width - 20) + 10
        )
      )
      .force(
        "y",
        d3.forceY().strength(0.1).y((d) =>
          d.type === "node"
            ? height / 2
            : d.parent
            ? height / 2
            : Math.random() * (height - 20) + 10
        )
      )
      .force("collide", d3.forceCollide().radius((d) => (d.type === "node" ? 100 : 40)))
      .on("tick", ticked);

    const link = svg.selectAll(".link")
      .data(links)
      .join("line")
      .attr("class", "link")
      .attr("stroke", "gray");

    const node = svg
      .selectAll(".node")
      .data(nodes)
      .join("circle")
      .attr("class", "node")
      .attr("r", (d) => (d.type === "node" ? 15 : 8))
      .attr("fill", (d) => {
        if (d.type === "pod" && (!d.parent || !d.ready)) {
          // Unassigned or not ready pods are red
          return "red";
        } else if (d.type === "pod") {
          // Assigned and ready pods are colored by deployment
          const deploymentColors = d3
            .scaleOrdinal(d3.schemeCategory10.filter((color) => colorDistance(color, red) > threshold && color !== purple) )
            .domain(data.pods.map((pod) => pod.deployment || pod.name));
          return deploymentColors(d.deployment || d.parent);
        } else if (d.type === "node") {
          // Nodes are always purple
          return "purple";
        }
        return "gray"; // Default color (shouldn't occur)
      })
      .call(
        d3
          .drag()
          .on("start", dragstarted)
          .on("drag", dragged)
          .on("end", dragended)
      );

    const nodeLabels = svg.selectAll(".node-label")
      .data(nodes)
      .join("text")
      .attr("class", "node-label")
      .attr("x", (d) => d.x)
      .attr("y", (d) => d.y - 20)
      .attr("text-anchor", "middle")
      .style("font-size", "12px")
      .style("fill", (d) => (d.type === "pod" && (!d.parent || !d.ready) ? "red" : "black"))
      .text((d) => (d.type === "pod" ? (displayMode === "pod" ? d.id : d.deployment) : d.id));

      function ticked() {
        link
          .attr("x1", (d) => Math.max(0, Math.min(width, d.source.x)))
          .attr("y1", (d) => Math.max(0, Math.min(height, d.source.y)))
          .attr("x2", (d) => Math.max(0, Math.min(width, d.target.x)))
          .attr("y2", (d) => Math.max(0, Math.min(height, d.target.y)));
      
        node
          .attr("cx", (d) => {
            const radius = d.type === "node" ? 15 : 8; // Radius of node or pod
            return (d.x = Math.max(radius, Math.min(width - radius, d.x)));
          })
          .attr("cy", (d) => {
            const radius = d.type === "node" ? 15 : 8; // Radius of node or pod
            return (d.y = Math.max(radius, Math.min(height - radius, d.y)));
          });
      
        nodeLabels
          .attr("x", function (d) {
            const labelWidth = this.getComputedTextLength(); // Dynamic width adjustment
            return Math.max(
              labelWidth / 2,
              Math.min(width - labelWidth / 2, d.x)
            );
          })
          .attr("y", (d) => Math.max(20, Math.min(height - 20, d.y - 20))); // Prevent clipping at top/bottom
      }
      

    function dragstarted(event, d) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x;
      d.fy = d.y;
    }

    function dragged(event, d) {
      d.fx = event.x;
      d.fy = event.y;
    }

    function dragended(event, d) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null;
      d.fy = null;
    }
  }, [data, displayMode]);

  return (
    <div>
      <div style={{ marginBottom: "10px" }}>
        <label>
          Display:
          <select value={displayMode} onChange={(e) => setDisplayMode(e.target.value)}>
            <option value="pod">Pod Name</option>
            <option value="deployment">Deployment Name</option>
          </select>
        </label>
      </div>
      <svg ref={svgRef}></svg>
    </div>
  );
};

export default KuPoVi;
