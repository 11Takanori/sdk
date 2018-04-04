// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Future;

import 'package:expect/expect.dart' show Expect;

import 'package:front_end/src/api_prototype/compiler_options.dart'
    show CompilerOptions;

import 'package:front_end/src/api_prototype/incremental_kernel_generator.dart'
    show IncrementalKernelGenerator;

import 'package:front_end/src/compute_platform_binaries_location.dart'
    show computePlatformBinariesLocation;

import 'package:front_end/src/fasta/fasta_codes.dart' show LocatedMessage;

import 'package:front_end/src/fasta/incremental_compiler.dart'
    show IncrementalCompiler;

import 'package:front_end/src/fasta/kernel/utils.dart' show serializeComponent;

import 'package:front_end/src/fasta/severity.dart' show Severity;

import 'package:kernel/kernel.dart' show Component, Library, Reference;

import 'package:kernel/text/ast_to_text.dart'
    show globalDebuggingNames, NameSystem;

import 'package:testing/testing.dart'
    show Chain, ChainContext, Result, Step, TestDescription, runMe;

main([List<String> arguments = const []]) =>
    runMe(arguments, createContext, "../testing.json");

Future<Context> createContext(
    Chain suite, Map<String, String> environment) async {
  return new Context();
}

class Context extends ChainContext {
  final List<Step> steps = const <Step>[
    const RunTest(),
  ];

  // Override special handling of negative tests.
  @override
  Result processTestResult(
      TestDescription description, Result result, bool last) {
    return result;
  }

  IncrementalCompiler compiler;
}

CompilerOptions getOptions(bool strong) {
  final Uri sdkRoot = computePlatformBinariesLocation();
  var options = new CompilerOptions()
    ..sdkRoot = sdkRoot
    ..librariesSpecificationUri = Uri.base.resolve("sdk/lib/libraries.json")
    ..onProblem = (LocatedMessage message, Severity severity, String formatted,
        int line, int column) {
      // ignore
    }
    ..strongMode = strong;
  if (strong) {
    options.sdkSummary =
        computePlatformBinariesLocation().resolve("vm_platform_strong.dill");
  } else {
    options.sdkSummary =
        computePlatformBinariesLocation().resolve("vm_platform.dill");
  }
  return options;
}

class RunTest extends Step<TestDescription, TestDescription, Context> {
  const RunTest();

  String get name => "run test";

  Future<Result<TestDescription>> run(
      TestDescription description, Context context) async {
    Uri uri = description.uri;

    // "One shot compile"
    bool oneShotFailed = false;
    List<int> oneShotSerialized;
    try {
      IncrementalCompiler compiler =
          new IncrementalKernelGenerator(getOptions(true), uri);
      oneShotSerialized = postProcess(await compiler.computeDelta());
    } catch (e) {
      oneShotFailed = true;
    }

    // Bulk
    bool bulkFailed = false;
    List<int> bulkSerialized;
    try {
      globalDebuggingNames = new NameSystem();
      if (context.compiler == null) {
        context.compiler =
            new IncrementalKernelGenerator(getOptions(true), uri);
      }
      Component bulkCompiledComponent = await context.compiler
          .computeDelta(entryPoint: uri, fullComponent: true);
      bulkSerialized = postProcess(bulkCompiledComponent);
    } catch (e) {
      bulkFailed = true;
    }

    // Compile again - the serialized output should be the same.
    bool bulk2Failed = false;
    List<int> bulkSerialized2;
    try {
      globalDebuggingNames = new NameSystem();
      if (context.compiler == null) {
        context.compiler =
            new IncrementalKernelGenerator(getOptions(true), uri);
      }
      Component bulkCompiledComponent = await context.compiler
          .computeDelta(entryPoint: uri, fullComponent: true);
      bulkSerialized2 = postProcess(bulkCompiledComponent);
    } catch (e) {
      bulk2Failed = true;
    }

    if (bulkFailed || oneShotFailed) {
      if (bulkFailed != oneShotFailed) {
        throw "Bulk-compiler failed: $bulkFailed; "
            "one-shot failed: $oneShotFailed";
      }
    } else {
      checkIsEqual(oneShotSerialized, bulkSerialized);
    }

    if (bulkFailed || bulk2Failed) {
      if (bulkFailed != bulk2Failed) {
        throw "Bulk-compiler failed: $bulkFailed; "
            "second bulk-comile failed: $bulk2Failed";
      }
    } else {
      checkIsEqual(bulkSerialized, bulkSerialized2);
    }

    return pass(description);
  }

  List<int> postProcess(Component c) {
    c.libraries.sort((l1, l2) {
      return l1.fileUri.toString().compareTo(l2.fileUri.toString());
    });

    c.computeCanonicalNames();
    for (Library library in c.libraries) {
      library.additionalExports.sort((Reference r1, Reference r2) {
        return r1.canonicalName
            .toString()
            .compareTo(r2.canonicalName.toString());
      });
    }

    return serializeComponent(c);
  }

  void checkIsEqual(List<int> a, List<int> b) {
    int length = a.length;
    if (b.length < length) {
      length = b.length;
    }
    for (int i = 0; i < length; ++i) {
      if (a[i] != b[i]) {
        Expect.fail("Data differs at byte ${i+1}.");
      }
    }
    Expect.equals(a.length, b.length);
  }
}