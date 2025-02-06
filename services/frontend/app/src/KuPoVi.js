import React, { useEffect, useRef, useState } from "react";
import * as d3 from "d3";

const KuPoVi = () => {
  const svgRef = useRef();
  const width = 800;
  const height = 600;
  const [data, setData] = useState({ nodes: [], pods: [] });
  const [previousData, setPreviousData] = useState(null);

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

    const svg = d3.select(svgRef.current)
      .attr("width", width)
      .attr("height", height);

    const nodes = [
      ...data.nodes.map((n) => ({ id: n.name, type: "node" })),
      ...data.pods.map((pod) => ({ id: pod.name, type: "pod", parent: pod.node }))
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

    const node = svg.selectAll(".node")
      .data(nodes)
      .join("circle")
      .attr("class", "node")
      .attr("r", (d) => (d.type === "node" ? 15 : 8))
      .attr("fill", (d) => (d.type === "node" ? "purple" : d.parent ? "green" : "red"))
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
      .style("fill", (d) => (d.type === "pod" && !d.parent ? "red" : "black"))
      .text((d) => d.id);

    function ticked() {
      link
        .attr("x1", (d) => Math.max(0, Math.min(width, d.source.x)))
        .attr("y1", (d) => Math.max(0, Math.min(height, d.source.y)))
        .attr("x2", (d) => Math.max(0, Math.min(width, d.target.x)))
        .attr("y2", (d) => Math.max(0, Math.min(height, d.target.y)));

      node
        .attr("cx", (d) => (d.x = Math.max(10, Math.min(width - 10, d.x))))
        .attr("cy", (d) => (d.y = Math.max(10, Math.min(height - 10, d.y))));

      nodeLabels
        .attr("x", function (d) {
          const labelWidth = this.getComputedTextLength(); // Dynamic width adjustment
          return Math.max(labelWidth / 2, Math.min(width - labelWidth / 2, d.x));
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
  }, [data]);

  return <svg ref={svgRef}></svg>;
};

export default KuPoVi;
