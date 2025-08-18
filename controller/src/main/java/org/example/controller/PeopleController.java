package org.example.controller;

import org.example.model.People;
import org.example.service.PeopleService;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Optional;

/**
 * REST controller exposing operations over People.
 */
@RestController
@RequestMapping("/people")
public class PeopleController {
    private final PeopleService service;

    public PeopleController() {
        this(new PeopleService());
    }

    public PeopleController(PeopleService service) {
        this.service = service;
    }

    @PostMapping
    public People create(@RequestParam String name, @RequestParam int age) {
        return service.create(name, age);
    }

    @GetMapping("/{id}")
    public Optional<People> get(@PathVariable Long id) {
        return service.getById(id);
    }

    @GetMapping
    public List<People> list() {
        return service.getAll();
    }

    @PutMapping("/{id}")
    public Optional<People> update(@PathVariable Long id, @RequestParam String name, @RequestParam int age) {
        return service.update(id, name, age);
    }

    @DeleteMapping("/{id}")
    public boolean delete(@PathVariable Long id) {
        return service.delete(id);
    }

    @GetMapping("/count")
    public long count() {
        return service.count();
    }
}
